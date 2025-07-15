//
//  File.swift
//  
//
//  Created by iMoe Nya on 2024/3/23.
//

import Foundation

public protocol JavaScriptEvaluating: AnyObject {
    typealias Completion = (Any) -> Void
    
    func evaluate(_ javaScript: JavaScript)
    func call(
        _ functionName: String,
        with parameter: JSON,
        completion: Completion?
    )
    func handleResponse(_ response: FromJS.Response)
    func initialize()
}

public typealias JavaScript = String

open class JavaScriptEvaluator: JavaScriptEvaluating {
    private let evaluating: (JavaScript) -> Void
    private var incrementalID: Int = 0
    private var completionByID: [Int: Completion] = [:]
    private var initialized = false
    private var waitingScripts: JavaScript = ""
    /// A timer. Everytime a new script / call comes in, enqueue it and activate the timer. The timer fires
    /// in 50ms to evaluate the enqueued scripts, before that, the evaluator enqueues all the new scripts
    /// and calls into `waitingScripts`.
    ///
    /// Using a timer avoids the hassle of managing a pending state.
    private lazy var metronome = Metronome(timeInterval: 0.05, queue: serialQueue)
    
    /// Serial queue to access properties and evaluate scripts.
    private let serialQueue = DispatchQueue(
        label: "JavaScriptEvaluator",
        target: .main
    )
    
    public init(evaluating: @escaping (JavaScript) -> Void) {
        self.evaluating = evaluating
        metronome.eventHandler = { [weak self] in
            guard let self else { return }
            flush()
        }
    }
    
    open func handleResponse(_ response: FromJS.Response) {
        serialQueue.async { [weak self] in
            guard
                let self,
                let completion = completionByID[response.id]
            else {
                return
            }
            defer {
                if response.completed {
                    completionByID.removeValue(forKey: response.id)
                }
            }
            completion(response.data)
        }
    }
    
    open func evaluate(_ javaScript: JavaScript) {
        serialQueue.async { [weak self] in
            guard let self else { return }
            enqueue(javaScript)
        }
    }
    
    open func initialize() {
        serialQueue.async { [weak self] in
            guard let self else { return }
            initialized = true
            metronome.resume()
        }
    }
    
    open func call(
        _ functionName: String,
        with parameter: JSON,
        completion: Completion?
    ) {
        serialQueue.async { [weak self] in
            guard let self else { return }
            defer { incrementalID += 1 }
            let id = incrementalID
            if let completion {
                completionByID[id] = completion
            }
            call(functionName, with: parameter, id: id)
        }
    }
    
    private func flush() {
        defer {
            metronome.suspend()
        }
        guard initialized else { return }
        guard !waitingScripts.isEmpty else { return }
        let scripts = waitingScripts
        waitingScripts = ""
        evaluating(scripts)
    }
    
    private func enqueue(_ script: String) {
        if waitingScripts.isEmpty {
            waitingScripts = script
        } else {
            waitingScripts.append("\n\(script)")
        }
        metronome.resume()
    }
    
    private func call(
        _ functionName: String,
        with parameter: JSON,
        id: Int
    ) {
          let  encoded = clStringConvert(parameter)
        let message = """
        {
            "method": "\(functionName)",
            "callbackId": \(id),
            "data": "\(encoded)"
        }
        """
        let script = "window._handleMessageFromNative(\(message))"
        enqueue(script)
    }

          //判断字符串是否为json
    func isValidJSON(_ string: String) -> Bool{
        if let data = string.data(using: .utf8){
            do{
                _ = try JSONSerialization.jsonObject(with: data,options: []);
                return true;
            }catch{
                return false;
            }
        }
        return false;
    }
    
    //添加转义
      func addEscapeCharactersToJSONString(_ string: String) -> String {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(string),
           let jsonEscaped = String(data: data, encoding: .utf8) {
            // 去掉两边的双引号（因为 encode(string) 会包一层引号）
            return String(jsonEscaped.dropFirst().dropLast())
        }
        return string
    }
    
    //字符串转换
    func clStringConvert(_ string:String) -> String{
        if(isValidJSON(string)){
            return addEscapeCharactersToJSONString(string);
        }else{
            return string;
        }
    }
}
