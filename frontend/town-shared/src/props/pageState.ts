// 道具页的状态：服务端给的道具目录、选中的一行、连接与等回执的命令，以及两个列表视图用到的页面部件和操作。
import type { ClientMsg } from '../protocol'
import type { Appearance, BodyNeed, Definition, PropCatalog, PropView } from './types'
import type { PlacingMap } from './placing'

export interface PropsDeps {
  send: (m: ClientMsg) => void
  /** 到「书与公告」页读这一篇 */
  read: (id: string) => void
  /** 到「书与公告」页看这块公告栏上的公告 */
  openBoard: (id: string) => void
  /** 摆道具用到的地图接口；没有就不提供摆道具 */
  map?: PlacingMap
  onLocate: (id: string, locale: string) => void
  onUpdate: (props: PropView[], spatial: PropCatalog['spatial']) => void
  /** 村民编号 → 名字（谁在用这件东西）；不认识的编号返回 undefined */
  personName?: (id: string) => string | undefined
  /** 游戏界面 */
  game: boolean
}

/** 等回执的命令；保存还记着定义与外观，成功后在本机存外观；摆道具的命令带 done，回执到了交给它 */
interface PendingOp {
  kind: string
  definition?: Definition
  appearance?: Appearance
  done?: (ok: boolean, message: string) => void
}

interface PropsPageState {
  catalog: PropCatalog | null
  /** 选中的一行：当前地图里是实例编号，道具库里是「定义@版本」 */
  selected: string
  connected: boolean
  /** 上次交给地图的道具结构；没变就不重画地图上的道具 */
  mapSignature: string
  /** 上次画列表时的目录；没变就不重画 */
  renderSignature: string
  /** 按请求编号 */
  pending: Map<string, PendingOp>
  /** 道具库详情里正等着确认删除的道具编号；目录每两秒刷新、重画详情，确认块靠它留住 */
  confirmDelete: string
}

export function createPropsPageState(): PropsPageState {
  return {
    catalog: null,
    selected: '',
    connected: false,
    mapSignature: '',
    renderSignature: '',
    pending: new Map(),
    confirmDelete: '',
  }
}

/** 当前地图与道具库两个视图共用的页面部件和操作 */
export interface PropsView {
  state: PropsPageState
  deps: PropsDeps
  game: boolean
  page: {
    list: HTMLElement
    detail: HTMLElement
    location: HTMLSelectElement
    purpose: { value: string }
  }
  localeName: (id: string) => string
  personName?: (id: string) => string | undefined
  needLabel: (need: BodyNeed) => string
  render(): void
  close(): void
  /** 以这个定义为底打开编辑器 */
  edit(d: Definition): void
  /** 放置、移除、删除这类要等回执的命令：登记请求编号，回包按编号对上后才提示结果；没连上时返回 false */
  sendWorldCommand(
    kind: string,
    command: (world_id: string, request_id: string) => ClientMsg,
    done?: (ok: boolean, message: string) => void
  ): boolean
  /** 删除这类做完以后列表里看不出痕迹的结果：写在顶上那行，目录刷新不擦掉，下一句话才换掉 */
  report(text: string): void
}
