import SwiftUI

extension Theme {
    /// 五款销毁道具的识别色。取自各自素材的主色，
    /// 深浅 / 高对比各给一档，统计条与指示点在两种外观下都可读。
    enum Device {
        /// 废纸篓：薄荷绿
        static let bin = Theme.dynamic(
            light: 0x4FB98C, dark: 0x6FD6A8,
            lightHighContrast: 0x247A57, darkHighContrast: 0x9BEBC4
        )
        /// 碎纸机：珊瑚粉
        static let shredder = Theme.dynamic(
            light: 0xE4786E, dark: 0xF39A8F,
            lightHighContrast: 0xA63F36, darkHighContrast: 0xFFC0B6
        )
        /// 壁炉：火焰橙
        static let fireplace = Theme.Accent.fire
        /// 邮筒：取自新素材深绿筒身的实测中位色 #507A60，
        /// 与废纸篓的薄荷绿靠明度 / 饱和度区分（分布条另有素材图标作第二重区分）。
        static let mailbox = Theme.dynamic(
            light: 0x507A60, dark: 0x83C6A2,
            lightHighContrast: 0x2C513D, darkHighContrast: 0xB4E8C8
        )
        /// 任意门：天蓝
        static let door = Theme.dynamic(
            light: 0x4C8FD6, dark: 0x74B4F2,
            lightHighContrast: 0x245E9E, darkHighContrast: 0xA6D4FF
        )
    }
}
