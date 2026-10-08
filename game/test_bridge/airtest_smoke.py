"""Airtest black-box smoke paths for the Windows Godot build.

The runner starts a visible debug game, keeps its window unobscured, navigates
three read-only startup routes, and records screenshots plus normalized
JSONL/SQLite evidence. It never enters a save or changes settings.
"""

# OpenCV and pywin32 expose their runtime APIs through compiled extensions that
# Pylint 2.14 cannot introspect in this environment.
# pylint: disable=no-member,c-extension-no-member

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import cv2
import numpy as np
import win32api
import win32con
import win32gui
import win32process
from airtest.core.api import connect_device


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
if str(REPOSITORY_ROOT) not in sys.path:
    sys.path.insert(0, str(REPOSITORY_ROOT))

from game.test_bridge.evidence_store import EvidenceStore  # pylint: disable=wrong-import-position,import-error  # noqa: E402


CLIENT_WIDTH = 1920
CLIENT_HEIGHT = 1080
STARTUP_CROP = (650, 420, 1270, 1010)
STARTUP_RETURN_THRESHOLD = 0.88
STARTUP_READY_CLIENT_STD = 30.0
STARTUP_READY_CROP_STD = 30.0
STARTUP_READY_STABILITY = 0.88
WINDOW_TITLE_SUFFIX = "(DEBUG)"


@dataclass(frozen=True)
class UiRoute:
    """One startup-page navigation path and its visual oracle."""

    name: str
    open_point: tuple[int, int]
    back_point: tuple[int, int]
    asset_path: Path
    threshold: float


def _routes(project_path: Path) -> tuple[UiRoute, ...]:
    return (
        UiRoute(
            name="load_game_and_back",
            open_point=(960, 748),
            back_point=(592, 927),
            asset_path=(
                project_path
                / "assets/ui/startup/final/load_game/load_game_open_paper_1672x941.png"
            ),
            threshold=0.85,
        ),
        UiRoute(
            name="game_settings_and_back",
            open_point=(1081, 831),
            back_point=(337, 168),
            asset_path=(
                project_path
                / "assets/ui/settings/final/shell/"
                / "audio_display_settings_runtime_shell_approved_v1.png"
            ),
            threshold=0.80,
        ),
        UiRoute(
            name="provider_settings_and_back",
            open_point=(839, 831),
            back_point=(309, 188),
            asset_path=(
                project_path
                / "assets/ui/provider_settings/component_assets/runtime/"
                / "composite/page_shell/provider_settings_page_dynamic_cards_v2.png"
            ),
            threshold=0.80,
        ),
    )


def _arguments() -> argparse.Namespace:
    project_default = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(
        description="Run safe Windows Airtest startup navigation smoke paths."
    )
    parser.add_argument(
        "--godot",
        type=Path,
        default=Path(r"D:\Godot\Godot_v4.7.2-stable_win64.exe"),
        help="Godot GUI executable.",
    )
    parser.add_argument(
        "--project",
        type=Path,
        default=project_default,
        help="Godot project directory.",
    )
    parser.add_argument(
        "--artifacts",
        type=Path,
        default=project_default / "test_bridge" / "artifacts",
        help="Existing evidence directory.",
    )
    parser.add_argument(
        "--repeat",
        type=int,
        default=1,
        help="Number of times to run each of the three paths.",
    )
    parser.add_argument(
        "--startup-timeout",
        type=float,
        default=45.0,
        help="Seconds allowed for the debug window and startup page.",
    )
    parser.add_argument(
        "--route-timeout",
        type=float,
        default=15.0,
        help="Seconds allowed for each route transition.",
    )
    return parser.parse_args()


def _validate_arguments(args: argparse.Namespace) -> None:
    if args.repeat < 1:
        raise ValueError("--repeat must be at least 1")
    if not args.godot.is_file():
        raise FileNotFoundError(f"Godot executable not found: {args.godot}")
    if not (args.project / "project.godot").is_file():
        raise FileNotFoundError(f"Godot project not found: {args.project}")
    if not args.artifacts.is_dir():
        raise FileNotFoundError(
            f"Evidence directory must already exist: {args.artifacts}"
        )
    for route in _routes(args.project):
        if not route.asset_path.is_file():
            raise FileNotFoundError(
                f"Visual oracle asset not found for {route.name}: {route.asset_path}"
            )


def _debug_window_for_process(process_id: int) -> int | None:
    matches: list[int] = []

    def collect(handle: int, _extra: Any) -> bool:
        if not win32gui.IsWindowVisible(handle):
            return True
        _, owner_process_id = win32process.GetWindowThreadProcessId(handle)
        if owner_process_id != process_id:
            return True
        if win32gui.GetWindowText(handle).endswith(WINDOW_TITLE_SUFFIX):
            matches.append(handle)
        return True

    win32gui.EnumWindows(collect, None)
    return matches[0] if matches else None


def _wait_for_window(process: subprocess.Popen[Any], timeout: float) -> int:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError(f"Godot exited before UI startup, code={process.returncode}")
        handle = _debug_window_for_process(process.pid)
        if handle is not None:
            return handle
        time.sleep(0.25)
    raise TimeoutError(f"Godot debug window did not appear within {timeout:.1f}s")


def _window_geometry(image: np.ndarray) -> tuple[int, int, int, int]:
    """Infer a 16:9 client inside the captured, DPI-scaled window frame."""

    height, width = image.shape[:2]
    scale = width / 1926.0
    border = max(round(3.0 * scale), 0)
    client_width = width - (2 * border)
    client_height = round(client_width * CLIENT_HEIGHT / CLIENT_WIDTH)
    title_and_border = height - client_height - border
    if client_width < 960 or client_height < 540 or title_and_border < 0:
        raise RuntimeError(
            "Godot window capture cannot contain a usable 16:9 client: "
            f"captured={width}x{height}"
        )
    return border, title_and_border, client_width, client_height


def _client_image(image: np.ndarray) -> tuple[np.ndarray, tuple[int, int]]:
    left, top, client_width, client_height = _window_geometry(image)
    client = image[top : top + client_height, left : left + client_width]
    if client.shape[:2] != (client_height, client_width):
        raise RuntimeError(f"Unexpected client capture shape: {client.shape}")
    return client, (left, top)


def _gray_correlation(actual: np.ndarray, expected: np.ndarray) -> float:
    if actual.shape != expected.shape:
        raise ValueError(f"Image shapes differ: {actual.shape} != {expected.shape}")
    actual_gray = cv2.cvtColor(actual, cv2.COLOR_BGR2GRAY)
    expected_gray = cv2.cvtColor(expected, cv2.COLOR_BGR2GRAY)
    score = cv2.matchTemplate(
        actual_gray,
        expected_gray,
        cv2.TM_CCOEFF_NORMED,
    )[0, 0]
    return float(score)


def _route_score(client: np.ndarray, route: UiRoute) -> float:
    asset = cv2.imread(str(route.asset_path), cv2.IMREAD_COLOR)
    if asset is None:
        raise RuntimeError(f"Unable to read visual oracle: {route.asset_path}")
    expected = cv2.resize(
        asset,
        (client.shape[1], client.shape[0]),
        interpolation=cv2.INTER_NEAREST,
    )
    return _gray_correlation(client, expected)


def _startup_crop(client: np.ndarray) -> np.ndarray:
    left, top, right, bottom = STARTUP_CROP
    scale_x = client.shape[1] / CLIENT_WIDTH
    scale_y = client.shape[0] / CLIENT_HEIGHT
    return client[
        round(top * scale_y) : round(bottom * scale_y),
        round(left * scale_x) : round(right * scale_x),
    ]


def _startup_score(client: np.ndarray, baseline: np.ndarray) -> float:
    return _gray_correlation(
        _startup_crop(client),
        _startup_crop(baseline),
    )


def _wait_for_startup_ready(
    device: Any,
    timeout: float,
) -> tuple[np.ndarray, np.ndarray, dict[str, float]]:
    """Wait for a stable, rendered startup page instead of a blank HWND."""

    deadline = time.monotonic() + timeout
    previous_client: np.ndarray | None = None
    last_client_std = 0.0
    last_crop_std = 0.0
    last_stability = float("-inf")
    while time.monotonic() < deadline:
        image = _capture(device)
        client, _ = _client_image(image)
        crop = _startup_crop(client)
        last_client_std = float(client.std())
        last_crop_std = float(crop.std())

        rendered = (
            last_client_std >= STARTUP_READY_CLIENT_STD
            and last_crop_std >= STARTUP_READY_CROP_STD
        )
        if rendered and previous_client is not None:
            last_stability = _startup_score(client, previous_client)
            if last_stability >= STARTUP_READY_STABILITY:
                return image, client, {
                    "clientStd": round(last_client_std, 4),
                    "cropStd": round(last_crop_std, 4),
                    "stability": round(last_stability, 6),
                }

        previous_client = client.copy() if rendered else None
        time.sleep(0.30)

    raise TimeoutError(
        "startup page did not become rendered and stable within "
        f"{timeout:.1f}s: clientStd={last_client_std:.2f}, "
        f"cropStd={last_crop_std:.2f}, stability={last_stability:.4f}"
    )


def _keep_window_visible(handle: int) -> None:
    """Keep screenshot pixels trustworthy without reading the system cursor."""

    win32gui.ShowWindow(handle, win32con.SW_RESTORE)
    win32gui.SetWindowPos(
        handle,
        win32con.HWND_TOPMOST,
        0,
        0,
        0,
        0,
        win32con.SWP_NOMOVE | win32con.SWP_NOSIZE | win32con.SWP_SHOWWINDOW,
    )
    current_thread = win32api.GetCurrentThreadId()
    foreground_handle = win32gui.GetForegroundWindow()
    foreground_thread = win32process.GetWindowThreadProcessId(foreground_handle)[0]
    target_thread = win32process.GetWindowThreadProcessId(handle)[0]
    attached_threads: list[int] = []
    try:
        for thread_id in (foreground_thread, target_thread):
            if thread_id != current_thread and thread_id not in attached_threads:
                win32process.AttachThreadInput(current_thread, thread_id, True)
                attached_threads.append(thread_id)
        win32gui.BringWindowToTop(handle)
        win32gui.SetForegroundWindow(handle)
        win32gui.SetActiveWindow(handle)
    except OSError as foreground_error:
        raise PermissionError(
            "Windows denied foreground control after input-thread attachment. "
            "Close any secure desktop or permission dialog, then retry."
        ) from foreground_error
    finally:
        for thread_id in reversed(attached_threads):
            win32process.AttachThreadInput(current_thread, thread_id, False)
    time.sleep(0.50)
    foreground = win32gui.GetForegroundWindow()
    if foreground != handle:
        raise RuntimeError(
            "Godot window did not become foreground: "
            f"expected={handle}, actual={foreground}"
        )


def _capture(device: Any, filename: Path | None = None) -> np.ndarray:
    return device.snapshot(filename=str(filename) if filename else None)


def _wait_for_route(
    device: Any,
    route: UiRoute,
    timeout: float,
) -> tuple[np.ndarray, float]:
    deadline = time.monotonic() + timeout
    last_image: np.ndarray | None = None
    last_score = float("-inf")
    while time.monotonic() < deadline:
        last_image = _capture(device)
        client, _ = _client_image(last_image)
        last_score = _route_score(client, route)
        if last_score >= route.threshold:
            return last_image, last_score
        time.sleep(0.30)
    raise AssertionError(
        f"{route.name} visual score {last_score:.4f} below {route.threshold:.2f}"
    )


def _wait_for_startup(
    device: Any,
    baseline: np.ndarray,
    timeout: float,
) -> tuple[np.ndarray, float]:
    deadline = time.monotonic() + timeout
    last_image: np.ndarray | None = None
    last_score = float("-inf")
    while time.monotonic() < deadline:
        last_image = _capture(device)
        client, _ = _client_image(last_image)
        last_score = _startup_score(client, baseline)
        if last_score >= STARTUP_RETURN_THRESHOLD:
            return last_image, last_score
        time.sleep(0.30)
    raise AssertionError(
        "startup return visual score "
        f"{last_score:.4f} below {STARTUP_RETURN_THRESHOLD:.2f}"
    )


def _click_client(handle: int, point: tuple[int, int]) -> None:
    """Send a client-area click directly to Godot without moving the real cursor."""

    _, _, client_width, client_height = win32gui.GetClientRect(handle)
    x_position = round(point[0] * client_width / CLIENT_WIDTH)
    y_position = round(point[1] * client_height / CLIENT_HEIGHT)
    message_position = (y_position << 16) | x_position
    win32gui.PostMessage(
        handle,
        win32con.WM_LBUTTONDOWN,
        win32con.MK_LBUTTON,
        message_position,
    )
    win32gui.PostMessage(
        handle,
        win32con.WM_LBUTTONUP,
        0,
        message_position,
    )


def _safe_filename(run_id: str, route: UiRoute, iteration: int, state: str) -> str:
    return f"{run_id}-{route.name}-{iteration:02d}-{state}.png"


# The explicit intermediate values make screenshots and scores diagnosable.
# pylint: disable=too-many-locals
def _run_path(
    *,
    device: Any,
    handle: int,
    route: UiRoute,
    iteration: int,
    baseline: np.ndarray,
    artifacts: Path,
    run_id: str,
    timeout: float,
) -> dict[str, Any]:
    started = time.perf_counter()
    _keep_window_visible(handle)
    current = _capture(device)
    current_client, _ = _client_image(current)
    before_score = _startup_score(current_client, baseline)
    if before_score < STARTUP_RETURN_THRESHOLD:
        raise AssertionError(
            f"{route.name} did not start on startup page: {before_score:.4f}"
        )

    _click_client(handle, route.open_point)
    route_image, route_score = _wait_for_route(device, route, timeout)
    route_path = artifacts / _safe_filename(
        run_id, route, iteration, "opened"
    )
    cv2.imwrite(str(route_path), route_image)

    _keep_window_visible(handle)
    _click_client(handle, route.back_point)
    returned_image, return_score = _wait_for_startup(device, baseline, timeout)
    returned_path = artifacts / _safe_filename(
        run_id, route, iteration, "returned"
    )
    cv2.imwrite(str(returned_path), returned_image)

    return {
        "durationMs": (time.perf_counter() - started) * 1000.0,
        "routeScore": round(route_score, 6),
        "returnScore": round(return_score, 6),
        "openedScreenshot": str(route_path.resolve()),
        "returnedScreenshot": str(returned_path.resolve()),
    }
# pylint: enable=too-many-locals


def _close_game(handle: int | None, process: subprocess.Popen[Any] | None) -> None:
    if handle and win32gui.IsWindow(handle):
        try:
            win32gui.SetWindowPos(
                handle,
                win32con.HWND_NOTOPMOST,
                0,
                0,
                0,
                0,
                win32con.SWP_NOMOVE | win32con.SWP_NOSIZE,
            )
            win32gui.PostMessage(handle, win32con.WM_CLOSE, 0, 0)
        except OSError:
            pass
    if process is None:
        return
    try:
        process.wait(timeout=5.0)
    except subprocess.TimeoutExpired:
        process.terminate()
        try:
            process.wait(timeout=3.0)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=3.0)


def main() -> int:  # pylint: disable=too-many-locals,too-many-statements
    """Run the configured UI paths and return a process-compatible exit code."""
    args = _arguments()
    _validate_arguments(args)
    routes = _routes(args.project)
    store = EvidenceStore(
        args.artifacts,
        "airtest",
        metadata={
            "repeat": args.repeat,
            "routes": [route.name for route in routes],
            "godot": str(args.godot.resolve()),
            "project": str(args.project.resolve()),
            "mode": "windows-image-black-box",
            "mutatesSave": False,
        },
    )
    process: subprocess.Popen[Any] | None = None
    handle: int | None = None
    passed = 0
    failed = 0
    run_started = time.perf_counter()
    game_log = args.artifacts / f"{store.run_id}-godot.log"

    try:
        with game_log.open("w", encoding="utf-8", newline="\n") as log_handle:
            process = subprocess.Popen(  # pylint: disable=consider-using-with
                [str(args.godot), "--path", str(args.project)],
                stdout=log_handle,
                stderr=subprocess.STDOUT,
                text=True,
                encoding="utf-8",
                errors="replace",
            )
            handle = _wait_for_window(process, args.startup_timeout)
            device = connect_device(f"Windows:///{handle}?foreground=false")
            _keep_window_visible(handle)
            baseline_image, baseline, readiness = _wait_for_startup_ready(
                device,
                args.startup_timeout,
            )
            baseline_path = args.artifacts / f"{store.run_id}-startup-baseline.png"
            cv2.imwrite(str(baseline_path), baseline_image)
            store.record(
                "startup_ready",
                name="startup",
                status="passed",
                details={
                    **readiness,
                    "baselineScreenshot": str(baseline_path.resolve()),
                },
            )
            print(
                "AIRTEST_STARTUP_READY "
                f"clientStd={readiness['clientStd']:.2f} "
                f"cropStd={readiness['cropStd']:.2f} "
                f"stability={readiness['stability']:.4f}",
                flush=True,
            )

            for iteration in range(1, args.repeat + 1):
                for route in routes:
                    path_started = time.perf_counter()
                    try:
                        details = _run_path(
                            device=device,
                            handle=handle,
                            route=route,
                            iteration=iteration,
                            baseline=baseline,
                            artifacts=args.artifacts,
                            run_id=store.run_id,
                            timeout=args.route_timeout,
                        )
                        passed += 1
                        store.record(
                            "ui_path",
                            name=route.name,
                            status="passed",
                            duration_ms=details["durationMs"],
                            details={"iteration": iteration, **details},
                        )
                        print(
                            f"AIRTEST_PATH_PASS name={route.name} "
                            f"iteration={iteration} "
                            f"routeScore={details['routeScore']:.4f} "
                            f"returnScore={details['returnScore']:.4f}",
                            flush=True,
                        )
                    except Exception as error:  # pylint: disable=broad-except
                        failed += 1
                        failure_path = (
                            args.artifacts
                            / _safe_filename(
                                store.run_id, route, iteration, "failure"
                            )
                        )
                        try:
                            _capture(device, failure_path)
                        except Exception:  # pylint: disable=broad-except
                            pass
                        store.record(
                            "ui_path",
                            name=route.name,
                            status="failed",
                            duration_ms=(time.perf_counter() - path_started)
                            * 1000.0,
                            error_type=type(error).__name__,
                            message=str(error),
                            details={
                                "iteration": iteration,
                                "failureScreenshot": str(failure_path.resolve()),
                            },
                        )
                        print(
                            f"AIRTEST_PATH_FAIL name={route.name} "
                            f"iteration={iteration} error={error}",
                            file=sys.stderr,
                            flush=True,
                        )
                        raise
    except Exception as error:  # pylint: disable=broad-except
        if failed == 0:
            failed = 1
            store.record(
                "runner_error",
                name="airtest",
                status="failed",
                error_type=type(error).__name__,
                message=str(error),
                details={"godotLog": str(game_log.resolve())},
            )
        print(f"AIRTEST_RUN_FAIL error={error}", file=sys.stderr, flush=True)
    finally:
        _close_game(handle, process)
        total = passed + failed
        duration_ms = (time.perf_counter() - run_started) * 1000.0
        store.finish(
            status="passed" if failed == 0 else "failed",
            total=total,
            passed=passed,
            failed=failed,
            skipped=0,
            other=0,
            duration_ms=duration_ms,
        )

    summary = {
        "runId": store.run_id,
        "status": "passed" if failed == 0 else "failed",
        "total": passed + failed,
        "passed": passed,
        "failed": failed,
        "repeat": args.repeat,
        "evidenceJsonl": str(store.jsonl_path),
        "evidenceSqlite": str(store.sqlite_path),
        "godotLog": str(game_log),
    }
    print(json.dumps(summary, ensure_ascii=False, sort_keys=True), flush=True)
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
