import ArgumentParser
import agtermCore

extension Session {
    struct Reconnect: RequestCommand {
        static let configuration = CommandConfiguration(
            abstract: "Reconnect a pane attached from another Mac.",
            discussion: """
                A pane waiting to reconnect retries now, as a key on it does. A pane whose link froze before \
                ssh noticed is attached again from scratch; the program on the other Mac keeps running. \
                Read each pane's `connection` from `tree`.
                """)
        @Option(name: .long, help: "Which pane: primary/left/top or split/right/bottom. Defaults to primary.") var pane: String?
        @OptionGroup var target: TargetOptions
        @OptionGroup var options: ClientOptions

        func validate() throws { try validatePaneArgument(pane) }

        func makeRequest() throws -> ControlRequest {
            ControlRequest(cmd: .sessionReconnect, target: target.target, args: options.withWindow(ControlArgs(pane: pane)))
        }
    }
}
