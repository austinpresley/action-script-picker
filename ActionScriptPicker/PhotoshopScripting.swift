import AppKit
import Foundation

enum PhotoshopQueryError: LocalizedError {
    case couldNotCompile(String)
    case automationPermissionDenied(String)
    case executionFailed(String)
    case noStringResult
    case timedOut

    var errorDescription: String? {
        switch self {
        case .couldNotCompile:
            return String(localized: "The Photoshop query could not be prepared.")
        case .automationPermissionDenied:
            return String(localized: "Automation permission is required to read actions from Photoshop.")
        case .executionFailed:
            return String(localized: "Photoshop could not return its loaded actions.")
        case .noStringResult:
            return String(localized: "Photoshop returned an unexpected result.")
        case .timedOut:
            return String(localized: "Photoshop did not respond within 15 seconds.")
        }
    }

    var details: String {
        switch self {
        case .couldNotCompile(let details),
             .automationPermissionDenied(let details),
             .executionFailed(let details):
            return details
        case .noStringResult:
            return "The AppleScript completed without a string result."
        case .timedOut:
            return "The action query exceeded the 15-second timeout."
        }
    }
}

protocol PhotoshopQuerying: Sendable {
    func query(target: PhotoshopTarget) async throws -> ActionCatalog
}

protocol AppleScriptExecuting: Sendable {
    func execute(source: String, timeout: TimeInterval) async throws -> String
}

struct NativePhotoshopQueryService: PhotoshopQuerying, Sendable {
    let executor: any AppleScriptExecuting

    init(executor: any AppleScriptExecuting = NativeAppleScriptExecutor()) {
        self.executor = executor
    }

    func query(target: PhotoshopTarget) async throws -> ActionCatalog {
        let source = PhotoshopActionQuery.appleScript(for: target)
        do {
            let response = try await executor.execute(source: source, timeout: 15)
            return try ActionCatalogParser.parse(response)
        } catch let error as CatalogParsingError {
            throw error
        } catch {
            throw error
        }
    }
}

struct NativeAppleScriptExecutor: AppleScriptExecuting, Sendable {
    func execute(source: String, timeout: TimeInterval) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let gate = ScriptResultGate(continuation: continuation)

            DispatchQueue.global(qos: .userInitiated).async {
                guard let script = NSAppleScript(source: source) else {
                    gate.resolve(.failure(PhotoshopQueryError.couldNotCompile("NSAppleScript could not create a script from the query source.")))
                    return
                }

                var errorInfo: NSDictionary?
                let result = script.executeAndReturnError(&errorInfo)
                if let errorInfo {
                    let details = Self.describe(errorInfo)
                    let number = (errorInfo[NSAppleScript.errorNumber] as? NSNumber)?.intValue
                    if number == -1743 || number == -1744 {
                        gate.resolve(.failure(PhotoshopQueryError.automationPermissionDenied(details)))
                    } else {
                        gate.resolve(.failure(PhotoshopQueryError.executionFailed(details)))
                    }
                    return
                }

                guard let value = result.stringValue else {
                    gate.resolve(.failure(PhotoshopQueryError.noStringResult))
                    return
                }
                gate.resolve(.success(value))
            }

            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout) {
                gate.resolve(.failure(PhotoshopQueryError.timedOut))
            }
        }
    }

    private static func describe(_ errorInfo: NSDictionary) -> String {
        errorInfo
            .map { "\($0.key): \($0.value)" }
            .sorted()
            .joined(separator: "\n")
    }
}

private final class ScriptResultGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Error>?

    init(continuation: CheckedContinuation<String, Error>) {
        self.continuation = continuation
    }

    func resolve(_ result: Result<String, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }
}

enum PhotoshopActionQuery {
    static func appleScript(for target: PhotoshopTarget) -> String {
        let application = AppleScriptString.expression(for: target.canonicalPath)
        let javaScript = AppleScriptString.expression(for: javaScriptSource)
        return """
        tell application \(application)
            set actionDataJSON to do javascript \(javaScript)
            return actionDataJSON
        end tell
        """ + "\n"
    }

    static let javaScriptSource = #"""
    (function () {
        function typeID(value) { return charIDToTypeID(value); }

        function quoteJSON(value) {
            return '"' + value.replace(/[\\"\u0000-\u001f]/g, function (character) {
                var escapes = {
                    '"': '\\"',
                    '\\': '\\\\',
                    '\b': '\\b',
                    '\f': '\\f',
                    '\n': '\\n',
                    '\r': '\\r',
                    '\t': '\\t'
                };
                if (escapes[character]) { return escapes[character]; }
                var hex = character.charCodeAt(0).toString(16);
                return '\\u' + ('0000' + hex).slice(-4);
            }) + '"';
        }

        function stringifyJSON(value) {
            var index;
            var parts;
            if (value === null) { return 'null'; }
            if (typeof value === 'string') { return quoteJSON(value); }
            if (typeof value === 'number') { return isFinite(value) ? String(value) : 'null'; }
            if (typeof value === 'boolean') { return value ? 'true' : 'false'; }
            if (Object.prototype.toString.call(value) === '[object Array]') {
                parts = [];
                for (index = 0; index < value.length; index += 1) {
                    parts.push(stringifyJSON(value[index]));
                }
                return '[' + parts.join(',') + ']';
            }
            if (typeof value === 'object') {
                parts = [];
                for (index in value) {
                    if (Object.prototype.hasOwnProperty.call(value, index)) {
                        parts.push(quoteJSON(index) + ':' + stringifyJSON(value[index]));
                    }
                }
                return '{' + parts.join(',') + '}';
            }
            return 'null';
        }

        var sets = [];
        var applicationReference = new ActionReference();
        applicationReference.putProperty(typeID('Prpr'), stringIDToTypeID('numberOfActionSets'));
        applicationReference.putEnumerated(typeID('capp'), typeID('Ordn'), typeID('Trgt'));
        var applicationDescriptor = executeActionGet(applicationReference);
        var setCount = applicationDescriptor.getInteger(stringIDToTypeID('numberOfActionSets'));

        for (var setIndex = 1; setIndex <= setCount; setIndex += 1) {
            var setReference = new ActionReference();
            setReference.putIndex(typeID('ASet'), setIndex);
            var setDescriptor = executeActionGet(setReference);
            var actionCount = setDescriptor.getInteger(typeID('NmbC'));
            var actions = [];

            for (var actionIndex = 1; actionIndex <= actionCount; actionIndex += 1) {
                var actionReference = new ActionReference();
                actionReference.putIndex(typeID('Actn'), actionIndex);
                actionReference.putIndex(typeID('ASet'), setIndex);
                var actionDescriptor = executeActionGet(actionReference);
                actions.push({ name: actionDescriptor.getString(typeID('Nm  ')) });
            }

            sets.push({
                name: setDescriptor.getString(typeID('Nm  ')),
                actions: actions
            });
        }

        return stringifyJSON({ sets: sets });
    }());
    """#
}
