import SwiftUI
import AppKit

/// 按键映射：可视化遥控器 + 分层（默认层兜底、应用层、手动层）。
struct KeymapView: View {

    @ObservedObject var model: SettingsModel

    @State private var selectedKey: RemoteKey = .ok
    @State private var selectedLayerID: String = KeyLayer.defaultID
    @State private var editingLayer: KeyLayer?
    @State private var showLayerEditor = false
    @State private var pendingDelete: KeyLayer?
    @State private var showCommandEditor = false
    @State private var commandDraft: CommandAction?
    @State private var showShortcutEditor = false
    @State private var shortcutDraft: KeyboardShortcut?

    private var layers: [KeyLayer] { model.config.keyLayers }

    private var selectedLayer: KeyLayer {
        layers.first(where: { $0.id == selectedLayerID })
            ?? layers.first(where: { $0.isDefault })
            ?? KeyLayer.makeDefault()
    }

    private var activeLayers: [KeyLayer] {
        KeymapResolver.activeLayers(layers,
                                    manualID: model.snapshot.manualLayerID,
                                    frontmostBundleID: model.snapshot.frontmostAppBundleID)
    }

    private var activeLayerIDs: Set<String> { Set(activeLayers.map(\.id)) }

    private var resolution: KeyResolution? {
        KeymapResolver.resolve(key: selectedKey, layers: layers,
                               manualID: model.snapshot.manualLayerID,
                               frontmostBundleID: model.snapshot.frontmostAppBundleID)
    }

    private var selectedBinding: KeyAction? {
        selectedLayer.action(for: selectedKey)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            remoteCard
                .frame(width: 306)
            VStack(spacing: 16) {
                layersCard
                keyCard
            }
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showLayerEditor) {
            KeyLayerEditorView(model: model, layer: editingLayer, onClose: {
                showLayerEditor = false
                editingLayer = nil
            }, onSaved: { id in
                selectedLayerID = id
            })
        }
        .sheet(isPresented: $showCommandEditor) {
            KeyCommandEditorView(initial: commandDraft, onClose: {
                showCommandEditor = false
                commandDraft = nil
            }, onSave: { action in
                model.setKeyBinding(layerID: selectedLayer.id, key: selectedKey,
                                    actionID: KeyAction.command(action).id)
                showCommandEditor = false
                commandDraft = nil
            })
        }
        .sheet(isPresented: $showShortcutEditor) {
            KeyShortcutEditorView(initial: shortcutDraft, onClose: {
                showShortcutEditor = false
                shortcutDraft = nil
            }, onSave: { shortcut in
                model.setKeyBinding(layerID: selectedLayer.id, key: selectedKey,
                                    actionID: KeyAction.keyboard(shortcut).id)
                showShortcutEditor = false
                shortcutDraft = nil
            })
        }
        .confirmationDialog("删除这个层？",
                            isPresented: Binding(get: { pendingDelete != nil },
                                                 set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button("删除层", role: .destructive) {
                if let layer = pendingDelete {
                    model.deleteKeyLayer(id: layer.id)
                    if selectedLayerID == layer.id { selectedLayerID = KeyLayer.defaultID }
                }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("该层的按键映射会一起删除；默认层不受影响。")
        }
        .onAppear {
            if !layers.contains(where: { $0.id == selectedLayerID }),
               let first = layers.first {
                selectedLayerID = first.id
            }
        }
    }

    // MARK: - 遥控器

    private var remoteCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            DuoCardHeader(title: "遥控器布局", icon: "dot.radiowaves.left.and.right",
                          tint: Duo.eel,
                          trailing: AnyView(DuoChip(text: "点击按键编辑",
                                                    color: Duo.wolf, background: Duo.polar)))

            ZStack {
                remoteBody
                remoteButtons
            }
            .frame(width: 270, height: 558)
            .frame(maxWidth: .infinity)

            HStack(spacing: 12) {
                legendDot(color: Duo.eel, text: "当前层显式绑定")
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Duo.eel)
                    Text("切层动作").font(.duo(9, .medium)).foregroundStyle(Duo.hare)
                }
                Spacer()
            }
            .padding(.horizontal, 4)

            Text("语音键由 ATVV 固定处理；音量 ± 是系统原生键，均不参与映射。")
                .font(.duo(9, .medium))
                .foregroundStyle(Duo.hare)
                .padding(.horizontal, 4)
        }
        .duoCard()
    }

    private let remoteScale: CGFloat = 0.9

    private static let remoteImage: NSImage? = {
        guard let image = NSImage(data: Data(remoteSVG.utf8)) else { return nil }
        image.size = NSSize(width: 300, height: 620)
        return image
    }()

    /// 按小米蓝牙遥控器 2 Pro 的实拍布局画的 SVG：细长银色机身、顶部两键、
    /// 大圆环方向键、左侧三键、右侧音量拨杆、右下麦克风。
    private static let remoteSVG = """
    <svg xmlns="http://www.w3.org/2000/svg" width="300" height="620" viewBox="0 0 300 620">
      <rect x="55" y="35" width="190" height="550" rx="36"
            fill="#FFFFFF" stroke="#2F2F31" stroke-width="1.6"/>
      <circle cx="95" cy="92" r="19" fill="none" stroke="#2F2F31" stroke-width="1.5"/>
      <circle cx="205" cy="92" r="19" fill="none" stroke="#2F2F31" stroke-width="1.5"/>
      <circle cx="150" cy="205" r="64" fill="none" stroke="#2F2F31" stroke-width="1.5"/>
      <circle cx="150" cy="205" r="21" fill="none" stroke="#2F2F31" stroke-width="1.5"/>
      <circle cx="115" cy="315" r="23" fill="none" stroke="#2F2F31" stroke-width="1.5"/>
      <circle cx="115" cy="375" r="23" fill="none" stroke="#2F2F31" stroke-width="1.5"/>
      <circle cx="115" cy="435" r="23" fill="none" stroke="#2F2F31" stroke-width="1.5"/>
      <rect x="166" y="293" width="44" height="104" rx="22"
            fill="none" stroke="#2F2F31" stroke-width="1.5"/>
      <line x1="176" y1="345" x2="200" y2="345" stroke="#2F2F31" stroke-width="1.1"
            opacity="0.55"/>
      <circle cx="187" cy="435" r="23" fill="none" stroke="#2F2F31" stroke-width="1.5"/>
      <circle cx="150" cy="520" r="3.5" fill="#9A9A9E"/>
    </svg>
    """

    private var remoteBody: some View {
        Group {
            if let image = Self.remoteImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(Color(hex: 0xE3E5E9))
            }
        }
        .frame(width: 270, height: 558)
    }

    private var remoteButtons: some View {
        ZStack {
            remoteKey(.power, at: CGPoint(x: 95, y: 92), size: 42,
                      icon: "power", iconSize: 14, highlightSize: 34)
            unsupportedIcon("mic.fill", at: CGPoint(x: 205, y: 92), iconSize: 13,
                            message: "语音键由 ATVV 固定处理，暂不支持映射")

            remoteKey(.back, at: CGPoint(x: 115, y: 315), size: 44,
                      icon: "arrow.uturn.backward", iconSize: 14, highlightSize: 41)
            remoteKey(.home, at: CGPoint(x: 115, y: 375), size: 44,
                      icon: "house.fill", iconSize: 14, highlightSize: 41)
            remoteKey(.menu, at: CGPoint(x: 115, y: 435), size: 44,
                      icon: "line.3.horizontal", iconSize: 14, highlightSize: 41)

            remoteKey(.up, at: CGPoint(x: 150, y: 158), size: 42,
                      icon: "chevron.up", iconSize: 14, highlightSize: 38)
            remoteKey(.down, at: CGPoint(x: 150, y: 252), size: 42,
                      icon: "chevron.down", iconSize: 14, highlightSize: 38)
            remoteKey(.left, at: CGPoint(x: 105, y: 205), size: 42,
                      icon: "chevron.left", iconSize: 14, highlightSize: 38)
            remoteKey(.right, at: CGPoint(x: 195, y: 205), size: 42,
                      icon: "chevron.right", iconSize: 14, highlightSize: 38)
            remoteKey(.ok, at: CGPoint(x: 150, y: 205), size: 46,
                      text: "OK", iconSize: 10, selectionSize: 44)

            unsupportedIcon("plus", at: CGPoint(x: 188, y: 315), iconSize: 12,
                            message: "音量键是系统原生键，暂不支持映射")
            unsupportedIcon("minus", at: CGPoint(x: 188, y: 375), iconSize: 12,
                            message: "音量键是系统原生键，暂不支持映射")

            remoteKey(.tv, at: CGPoint(x: 187, y: 435), size: 44,
                      icon: "tv", iconSize: 14, highlightSize: 41)

            Text("Xiaomi")
                .font(.system(size: 7, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.gray.opacity(0.55))
                .position(x: 150 * remoteScale, y: 552 * remoteScale)
        }
        .frame(width: 270, height: 558)
    }

    private func remoteKey(_ key: RemoteKey, at point: CGPoint, size: CGFloat,
                           icon: String? = nil, text: String? = nil,
                           iconSize: CGFloat = 13,
                           selectionSize: CGFloat? = nil,
                           highlightSize: CGFloat = 40) -> some View {
        let selected = selectedKey == key
        let binding = selectedLayer.action(for: key)
        let showBindingBadge = binding != nil
            && (!selectedLayer.isDefault || binding?.isLayerSwitch == true)
        return Button {
            selectedKey = key
        } label: {
            ZStack {
                if selected {
                    Circle()
                        .fill(Duo.eel)
                        .frame(width: highlightSize, height: highlightSize)
                }
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: iconSize, weight: .bold))
                        .foregroundStyle(selected ? Duo.white : Duo.eel)
                }
                if let text {
                    Text(text)
                        .font(.duo(10, .heavy))
                        .foregroundStyle(selected ? Duo.white : Duo.eel)
                }

                if selected {
                    let ring = selectionSize ?? (highlightSize + 2)
                    Circle()
                        .strokeBorder(Duo.eel, lineWidth: 2)
                        .frame(width: ring, height: ring)
                }

                if let binding, showBindingBadge {
                    Image(systemName: binding.isLayerSwitch ? "arrow.triangle.branch" : "circle.fill")
                        .font(.system(size: binding.isLayerSwitch ? 7 : 5, weight: .black))
                        .foregroundStyle(Duo.eel)
                        .frame(width: 13, height: 13)
                        .background(Circle().fill(Duo.white))
                        .offset(x: size / 2 - 5, y: -size / 2 + 5)
                }
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .position(x: point.x * remoteScale, y: point.y * remoteScale)
        .help("\(key.displayName)：\(binding?.title(layers: layers) ?? "穿透到下一层")")
    }

    private func unsupportedIcon(_ icon: String, at point: CGPoint,
                                 iconSize: CGFloat, message: String) -> some View {
        Button {
            Toast.shared.show(message, duration: 1.8)
        } label: {
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .bold))
                .foregroundStyle(Duo.wolf)
                .frame(width: 38, height: 38)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .position(x: point.x * remoteScale, y: point.y * remoteScale)
        .help(message)
    }

    private func legendDot(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text.localized).font(.duo(9, .medium)).foregroundStyle(Duo.hare)
        }
    }

    // MARK: - 层

    private var layersCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            DuoCardHeader(title: "层", icon: "square.stack.3d.up.fill", tint: Duo.lily,
                          trailing: AnyView(
                            Button("添加层") {
                                editingLayer = nil
                                showLayerEditor = true
                            }
                            .buttonStyle(DuoSecondaryButtonStyle(height: 30))
                          ))

            Text("解析顺序：手动层 → 匹配前台应用的层 → 默认层；某个键在当前层没绑定时自动穿透到下一层，默认层永远兜底。")
                .font(.duo(10, .medium))
                .foregroundStyle(Duo.wolf)
                .fixedSize(horizontal: false, vertical: true)

            if let manual = model.snapshot.manualLayerID,
               let layer = layers.first(where: { $0.id == manual }) {
                HStack(spacing: 8) {
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Duo.whale)
                    Text(localized("手动层：%@", layer.name))
                        .font(.duo(10, .bold))
                        .foregroundStyle(Duo.eel)
                    Spacer()
                    Button("取消") { model.setManualLayer(nil) }
                        .buttonStyle(DuoSecondaryButtonStyle(height: 24))
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Duo.iguana))
            }

            ForEach(layers) { layer in
                layerRow(layer)
            }
        }
        .duoCard()
    }

    private func layerRow(_ layer: KeyLayer) -> some View {
        let selected = layer.id == selectedLayerID
        let isActive = activeLayerIDs.contains(layer.id)
        let manual = model.snapshot.manualLayerID == layer.id
        return HStack(alignment: .top, spacing: 10) {
            Button {
                selectedLayerID = layer.id
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(layer.name)
                            .font(.duo(13, .heavy))
                            .foregroundStyle(Duo.eel)
                        if layer.isDefault {
                            Text("兜底")
                                .font(.duo(8, .heavy))
                                .foregroundStyle(Duo.beeDark)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Duo.beeLight))
                        }
                        if manual {
                            Text("手动")
                                .font(.duo(8, .heavy))
                                .foregroundStyle(Duo.whale)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Duo.iguana))
                        } else if isActive && !layer.isDefault {
                            Text("生效中")
                                .font(.duo(8, .heavy))
                                .foregroundStyle(Duo.treeFrog)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Duo.seaSponge))
                        }
                    }

                    Text(conditionText(layer))
                        .font(.duo(9, .medium))
                        .foregroundStyle(Duo.wolf)

                    if let summary = switchSummary(layer) {
                        Text(summary)
                            .font(.duo(9, .medium))
                            .foregroundStyle(Duo.whale)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 6) {
                if !layer.isDefault {
                    Button(manual ? "取消" : "激活") {
                        model.setManualLayer(manual ? nil : layer.id)
                    }
                    .buttonStyle(DuoSecondaryButtonStyle(height: 26))

                    Button {
                        editingLayer = layer
                        showLayerEditor = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Duo.wolf)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Duo.polar))
                    }
                    .buttonStyle(.plain)

                    Button {
                        pendingDelete = layer
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Duo.cardinal)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(Duo.walkingFish))
                    }
                    .buttonStyle(.plain)
                } else {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Duo.hare)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? Duo.seaSponge : Duo.polar)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(selected ? Duo.treeFrog.opacity(0.5) : Duo.swan,
                              lineWidth: selected ? 2 : 1)
        )
    }

    private func conditionText(_ layer: KeyLayer) -> String {
        if layer.isDefault { return "永远兜底；任何层未绑定的键都会落到这里" }
        if let bundle = layer.appBundleID, !bundle.isEmpty {
            return localized("前台应用：%@", appName(bundle))
        }
        return "手动激活"
    }

    private func switchSummary(_ layer: KeyLayer) -> String? {
        let parts = layer.bindings.compactMap { raw, actionID -> String? in
            guard let key = RemoteKey(rawValue: raw),
                  let action = KeyAction(id: actionID),
                  action.isLayerSwitch else { return nil }
            let target: String
            switch action {
            case .layer(let id):
                target = layers.first(where: { $0.id == id })?.name ?? "已删除的层"
            default:
                target = "默认层"
            }
            return "\(key.displayName)→\(target)"
        }.sorted()
        return parts.isEmpty ? nil : localized("切层键：%@", parts.joined(separator: " · "))
    }

    // MARK: - 按键详情

    private var keyCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            DuoCardHeader(title: localized("按键 · %@", selectedKey.displayName),
                          icon: KeymapKeys.icon(selectedKey), tint: Duo.eel,
                          trailing: AnyView(
                            DuoChip(text: resolution?.action.shortTitle ?? "默认",
                                    color: Duo.eel, background: Duo.polar)
                          ))

            VStack(spacing: 0) {
                ForEach(activeLayers) { layer in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(layer.id == resolution?.layerID ? Duo.treeFrog : Duo.swan)
                            .frame(width: 6, height: 6)
                        Text(layer.name)
                            .font(.duo(11, .bold))
                            .foregroundStyle(Duo.eel)
                        if layer.isDefault {
                            Text("兜底")
                                .font(.duo(8, .heavy))
                                .foregroundStyle(Duo.hare)
                        }
                        Spacer()
                        if let action = layer.action(for: selectedKey) {
                            HStack(spacing: 4) {
                                Image(systemName: action.icon)
                                    .font(.system(size: 9, weight: .bold))
                                Text(action.title(layers: layers))
                                    .font(.duo(10, .bold))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.trailing)
                            }
                            .foregroundStyle(layer.id == resolution?.layerID ? Duo.treeFrog : Duo.wolf)
                        } else {
                            Text("未绑定 → 穿透")
                                .font(.duo(10, .medium))
                                .foregroundStyle(Duo.hare)
                        }
                    }
                    .padding(.vertical, 7)
                    if layer.id != activeLayers.last?.id {
                        Divider().overlay(Duo.swan.opacity(0.6))
                    }
                }
            }
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Duo.polar)
            )

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(localized("在「%@」中的响应", selectedLayer.name))
                        .font(.duo(12, .bold))
                        .foregroundStyle(Duo.eel)
                    Text(selectedLayer.isDefault
                         ? localized("默认层的绑定会被其他层覆盖，未绑定则继续往下兜底")
                         : localized("只影响这一层；未设置的键会穿透到默认层"))
                        .font(.duo(9, .medium))
                        .foregroundStyle(Duo.wolf)
                }
                Spacer()
                actionPicker
            }

            if let shortcut = selectedBinding?.keyboardShortcut {
                HStack(spacing: 8) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Duo.eel)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("发送按键")
                            .font(.duo(10, .heavy))
                            .foregroundStyle(Duo.eel)
                        Text(shortcut.displayName)
                            .font(.duo(11, .bold))
                            .foregroundStyle(Duo.wolf)
                    }
                    Spacer()
                    Button("编辑") {
                        shortcutDraft = shortcut
                        showShortcutEditor = true
                    }
                    .buttonStyle(DuoSecondaryButtonStyle(height: 28))
                }
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Duo.polar))
            }

            if let command = selectedBinding?.commandAction {
                HStack(spacing: 8) {
                    Image(systemName: KeyAction.command(command).icon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Duo.eel)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("指令动作")
                            .font(.duo(10, .heavy))
                            .foregroundStyle(Duo.eel)
                        Text(command.summary)
                            .font(.duo(10, .medium))
                            .foregroundStyle(Duo.wolf)
                            .lineLimit(2)
                    }
                    Spacer()
                    Button("编辑") {
                        commandDraft = command
                        showCommandEditor = true
                    }
                    .buttonStyle(DuoSecondaryButtonStyle(height: 28))
                }
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Duo.polar))
            }

            if let binding = selectedBinding, binding.isLayerSwitch {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 10, weight: .bold))
                    Text(layerSwitchHint(binding))
                        .font(.duo(10, .bold))
                }
                .foregroundStyle(Duo.whale)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Duo.iguana))
            }

            HStack(spacing: 8) {
                if selectedBinding != nil {
                    Button("清除该键（穿透）") {
                        model.setKeyBinding(layerID: selectedLayer.id, key: selectedKey, actionID: nil)
                    }
                    .buttonStyle(DuoSecondaryButtonStyle(height: 30))
                }
                if selectedLayer.isDefault {
                    Button("恢复默认键位") {
                        var reset = KeyLayer.makeDefault()
                        reset.name = selectedLayer.name
                        model.upsertKeyLayer(reset)
                    }
                    .buttonStyle(DuoSecondaryButtonStyle(height: 30))
                }
                Spacer()
                if !activeLayerIDs.contains(selectedLayer.id) {
                    Text("该层当前未激活，仅在激活后生效")
                        .font(.duo(9, .medium))
                        .foregroundStyle(Duo.hare)
                }
            }
        }
        .duoCard()
    }

    private var actionPicker: some View {
        Picker("", selection: Binding(
            get: {
                if selectedBinding?.commandAction != nil { return "__command__" }
                if selectedBinding?.keyboardShortcut != nil { return "__keyboard__" }
                return selectedLayer.bindings[selectedKey.rawValue] ?? ""
            },
            set: { newValue in
                if newValue == "__command__" {
                    commandDraft = selectedBinding?.commandAction
                    showCommandEditor = true
                } else if newValue == "__keyboard__" {
                    shortcutDraft = selectedBinding?.keyboardShortcut
                    showShortcutEditor = true
                } else {
                    model.setKeyBinding(layerID: selectedLayer.id, key: selectedKey,
                                        actionID: newValue.isEmpty ? nil : newValue)
                }
            }
        )) {
            Text("未绑定（穿透）").tag("")
            Section("媒体") {
                ForEach([KeyAction.volumeUp, .volumeDown, .previousTrack, .nextTrack,
                         .playPause, .mute], id: \.self) { action in
                    Text(action.title(layers: layers)).tag(action.id)
                }
            }
            Section("系统") {
                ForEach([KeyAction.escape, .missionControl, .displaySleep], id: \.self) { action in
                    Text(action.title(layers: layers)).tag(action.id)
                }
            }
            Section("模式") {
                ForEach([KeyAction.mode(.forward), .mode(.command), .mode(.input)], id: \.self) { action in
                    Text(action.title(layers: layers)).tag(action.id)
                }
            }
            Section("层") {
                Text(KeyAction.defaultLayer.title(layers: layers)).tag(KeyAction.defaultLayer.id)
                ForEach(layers.filter { !$0.isDefault }) { layer in
                    Text(localized("切换到「%@」", layer.name)).tag(KeyAction.layer(layer.id).id)
                }
            }
            Section("键盘") {
                Text("发送键盘按键…").tag("__keyboard__")
            }
            Section("指令能力（与指令共用）") {
                Text("执行指令动作…").tag("__command__")
            }
            Section("其他") {
                Text(KeyAction.none.title(layers: layers)).tag(KeyAction.none.id)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 176)
    }

    private func layerSwitchHint(_ action: KeyAction) -> String {
        let target: String
        switch action {
        case .layer(let id):
            target = layers.first(where: { $0.id == id })?.name ?? "已删除的层"
        default:
            target = "默认层"
        }
        return localized("按下后手动层变为「%@」；再按一次同一键会取消", target)
    }

    private func appName(_ bundleID: String) -> String {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first?.localizedName ?? bundleID
    }
}

// MARK: - 层编辑

struct KeyLayerEditorView: View {

    @ObservedObject var model: SettingsModel
    let layer: KeyLayer?
    let onClose: () -> Void
    let onSaved: (String) -> Void

    @State private var name: String
    @State private var appBundleID: String
    @State private var apps: [RunningApp] = []

    private struct RunningApp: Identifiable {
        let id: String
        let name: String
    }

    init(model: SettingsModel, layer: KeyLayer?,
         onClose: @escaping () -> Void, onSaved: @escaping (String) -> Void) {
        self.model = model
        self.layer = layer
        self.onClose = onClose
        self.onSaved = onSaved
        _name = State(initialValue: layer?.name ?? "")
        _appBundleID = State(initialValue: layer?.appBundleID ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(layer == nil ? localized("添加层") : localized("编辑层"))
                .font(.duo(20, .heavy))
                .foregroundStyle(Duo.eel)

            VStack(alignment: .leading, spacing: 6) {
                Text("层名称").font(.duo(11, .bold)).foregroundStyle(Duo.eel)
                TextField("例如：游戏、剪辑", text: $name)
                    .textFieldStyle(.plain)
                    .font(.duo(13, .bold))
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Duo.polar))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("激活条件").font(.duo(11, .bold)).foregroundStyle(Duo.eel)
                Picker("", selection: $appBundleID) {
                    Text("手动激活（不自动）").tag("")
                    ForEach(apps) { app in
                        Text(app.name).tag(app.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)

                TextField("com.example.app（可手填）", text: $appBundleID)
                    .textFieldStyle(.plain)
                    .font(.duo(10, .medium))
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Duo.polar))

                Text("选择某个应用后，它在前台时这一层会自动生效；也可以手填 Bundle ID，或随时用按键切层 / 手动激活。")
                    .font(.duo(9, .medium))
                    .foregroundStyle(Duo.wolf)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("取消", action: onClose)
                    .buttonStyle(DuoSecondaryButtonStyle())
                Button("保存") {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    let updated = KeyLayer(
                        id: layer?.id ?? UUID().uuidString,
                        name: trimmed,
                        appBundleID: appBundleID.isEmpty ? nil : appBundleID,
                        bindings: layer?.bindings ?? [:]
                    )
                    model.upsertKeyLayer(updated)
                    onSaved(updated.id)
                    onClose()
                }
                .buttonStyle(DuoPrimaryButtonStyle())
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
        .background(Duo.white)
        .onAppear(perform: loadApps)
    }

    private func loadApps() {
        var seen = Set<String>()
        var list: [RunningApp] = []
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular,
                  let bundle = app.bundleIdentifier else { continue }
            guard seen.insert(bundle).inserted else { continue }
            list.append(RunningApp(id: bundle, name: app.localizedName ?? bundle))
        }
        if !appBundleID.isEmpty, !seen.contains(appBundleID) {
            list.append(RunningApp(id: appBundleID, name: appBundleID))
        }
        apps = list.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
