import SwiftUI
import WebKit

extension Tab {
    func matchingTextCount(in text: String) async -> Int {
        guard !text.isEmpty else { return 0 }
        let query = javaScriptLiteral(text)
        let source = """
        (() => {
            if (!document.body) return 0;
            const query = \(query).toLowerCase();
            const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
            let count = 0;
            for (let node = walker.nextNode(); node; node = walker.nextNode()) {
                count += node.nodeValue.toLowerCase().split(query).length - 1;
            }
            return count;
        })()
        """
        return await evaluateFind(source) as? Int ?? 0
    }

    func jumpToMatch(direction forward: Bool, in text: String) async -> Bool {
        guard !text.isEmpty else { return false }
        let query = javaScriptLiteral(text)
        let backwards = forward ? "false" : "true"
        let source = """
        (() => {
            window.getSelection().removeAllRanges();
            return window.find(\(query), false, \(backwards), true, false, true, false);
        })()
        """
        do {
            let value = try await webView.evaluateJavaScript(source)
            return value as? Bool ?? false
        } catch {
            diagnostic("navigation failed: \(error.localizedDescription)")
            return false
        }
    }

    private func evaluateFind(_ source: String) async -> Any? {
        do {
            return try await webView.evaluateJavaScript(source)
        } catch {
            diagnostic("page find failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func javaScriptLiteral(_ text: String) -> String {
        guard let data = try? JSONEncoder().encode(text),
              let encoded = String(data: data, encoding: .utf8)
        else { return "\"\"" }
        return encoded
    }
}

struct FindInPageOverlay: View {
    let browser: BrowserModel
    let tab: Tab

    @State private var text = ""
    @State private var total = 0
    @State private var current = 0
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    isFocused = false
                }

            HStack(spacing: 10) {
                Image(systemName: "text.magnifyingglass")
                    .foregroundStyle(.white.opacity(0.55))
                TextField("Find on Page", text: $text)
                    .foregroundStyle(.white)
                    .tint(LuneTheme.gold)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isFocused)

                if total > 0 {
                    Text("\(max(current, 1))/\(total)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                        .contentTransition(.numericText())
                }

                Button {
                    jump(forward: false)
                } label: {
                    Image(systemName: "chevron.up")
                        .frame(width: 28, height: 32)
                }
                Button {
                    jump(forward: true)
                } label: {
                    Image(systemName: "chevron.down")
                        .frame(width: 28, height: 32)
                }
                Button {
                    browser.overlay = .none
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 28, height: 32)
                }
            }
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(.white.opacity(0.75))
            .padding(.horizontal, 16)
            .frame(height: 58)
            .background(LuneTheme.panel.opacity(0.97), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
            .preferredColorScheme(.dark)
        }
        .onAppear {
            tab.onPageFinished = { matchText(text) }
            if let seed = browser.findPageSeed {
                text = seed
                browser.findPageSeed = nil
            }
            isFocused = true
        }
        .onChange(of: text) { _, newValue in
            matchText(newValue)
        }
        .onSubmit { jump(forward: true) }
        .onDisappear {
            searchTask?.cancel()
            tab.onPageFinished = nil
        }
        .onChange(of: isFocused) { _, focused in
            if !focused { browser.overlay = .none }
        }
    }

    private func matchText(_ query: String) {
        searchTask?.cancel()
        guard !query.isEmpty else {
            total = 0
            current = 0
            return
        }
        searchTask = Task { @MainActor in
            total = await tab.matchingTextCount(in: query)
            diagnostic("found \(total) for \(query)")
            current = total > 0 ? 1 : 0
            if total > 0 {
                _ = await tab.jumpToMatch(direction: true, in: query)
            }
        }
    }

    private func jump(forward: Bool) {
        guard !text.isEmpty else { return }
        searchTask?.cancel()
        searchTask = Task { @MainActor in
            if await tab.jumpToMatch(direction: forward, in: text) {
                current = forward ? (current % max(total, 1)) + 1 : (current + max(total, 1) - 2) % max(total, 1) + 1
            }
        }
    }
}
