//
//  APIService.swift
//
//  Created by Paolo Manna on 23/02/2017.
//

import CFNetwork
import CommonCrypto
import Security
import UIKit

// For SSL Certificate Pinning
var apiPublicKeyHash	= ""

/*
 A bit of explanation here:
 It would have been possible, and seemingly more natural, to use a serial DispatchQueue
 or OperationQueue to achieve the same serial behaviour for the service, however canceling a
 specific task would have been hard
 */

public class APIService {
	static var queueReqs: Bool			= true
	
	var session: URLSession!
	var headers: [String: String]
	var urlProtocol		= "https"
	var serviceString	= "localhost:8080"
	var basePath		= ""
	var tasks			= [URLSessionTask]()
	var lock			= NSLock()
	var isInBackground	= false
	var bkgndTaskId: UIBackgroundTaskIdentifier?
	var timeout: TimeInterval	= 30.0
#if DEBUG
	var timeStart: TimeInterval	= 0.0
	var dumpPayload				= false
#endif
	
	// MARK: - Methods
	
	public required init(token aToken: String? = nil) {
		if !apiPublicKeyHash.isEmpty {
			session	= URLSession(configuration: .ephemeral,
			       	             delegate: CloudSSLPinning(),
			       	             delegateQueue: nil)
		} else {
			session	= URLSession(configuration: .ephemeral)
		}
		
		headers = [String: String]()
        
		headers["Content-Type"]     = "application/json"	// This is going to change according to the request, but it's a reasonable default
		headers["Cache-Control"]    = "No-Cache"
		headers["Accept"]			= "*/*"
		headers["Accept-Encoding"]	= "gzip, deflate"
		
		if let token = aToken {
			headers["Authorization"]    = "Bearer " + token
		}
		
#if DEBUG
		let pInfo	= ProcessInfo.processInfo.environment
		
		if pInfo["DUMP_BODY"] != nil {
			dumpPayload	= true
		}
#endif
		// Prepare for background operation
		let nc = NotificationCenter.default
		
		nc.addObserver(self, selector: #selector(didEnterBackground(_:)), name: UIApplication.didEnterBackgroundNotification, object: nil)
		nc.addObserver(self, selector: #selector(willEnterForeground(_:)), name: UIApplication.willEnterForegroundNotification, object: nil)
	}
	
	deinit {
		NotificationCenter.default.removeObserver(self)
	}
	
	func update(token aToken: String?) {
		if let token = aToken {
			headers["Authorization"]    = "Bearer " + token
		} else {
			headers.removeValue(forKey: "Authorization")
		}
	}
	
	func endBackgroundOperation() {
		guard bkgndTaskId != nil else { return }
		
#if DEBUG
		print("]-]-]-] Ending background task")
#endif
		UIApplication.shared.endBackgroundTask(bkgndTaskId!)
		bkgndTaskId	= nil
	}
	
	@objc func didEnterBackground(_ notification: Notification) {
		bkgndTaskId	= UIApplication.shared.beginBackgroundTask(withName: "\(urlProtocol)://\(serviceString)\(basePath)") {
			self.endBackgroundOperation()
		}
		isInBackground	= true
		
#if DEBUG
		print("[-[-[-[ Starting background task")
#endif

		// Wait for a few seconds to give other part of the code time to queue something
		// Then, check if there's anything still queued, end background mode otherwise
		// This is called only as a safety check if there was nothing in the queue in the first place
		DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
			if self.lock.lock(before: Date.distantFuture) {
				if self.tasks.isEmpty { self.endBackgroundOperation() }
				self.lock.unlock()
			}
		}
	}
	
	@objc func willEnterForeground(_ notification: Notification) {
		isInBackground	= false
	}
	
	func enqueue(task: URLSessionDataTask) {
		// Add task to the queue: it will be removed when response arrives
		// Under lock to support multi-threading
		if lock.lock(before: Date.distantFuture) {
			tasks.append(task)
			
#if DEBUG
			print("Queueing task \(tasks.count)")
#endif
			// If it's the only element in the queue, start it
			if tasks.count == 1 {
#if DEBUG
				print("Starting task 1: \(task.originalRequest!.httpMethod!) \(task.originalRequest!.url!)")
				timeStart	= Date.timeIntervalSinceReferenceDate
#endif
				task.resume()
			}
			
			lock.unlock()
		}
	}
	
	func dequeue() {
		guard !tasks.isEmpty else { return }
		
		if lock.lock(before: Date.distantFuture) {
#if DEBUG
			print("Dequeueing task 1 of \(tasks.count): response took \(((Date.timeIntervalSinceReferenceDate - timeStart) * 1000.0).rounded() / 1000.0) secs")
#endif
			tasks.remove(at: 0)
			
			// If there's another element in the queue, start it
			if !tasks.isEmpty {
#if DEBUG
				print("Starting task 1 of \(tasks.count): \(tasks[0].originalRequest!.httpMethod!) \(tasks[0].originalRequest!.url!)")
				timeStart	= Date.timeIntervalSinceReferenceDate
#endif
				tasks[0].resume()
			} else if isInBackground, bkgndTaskId != nil {
				DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
					// If after a short time we're still empty, assume there's no need for background anymore
					if self.lock.lock(before: Date.distantFuture) {
						if self.tasks.isEmpty { self.endBackgroundOperation() }
						self.lock.unlock()
					}
				}
			}
			
			lock.unlock()
		}
	}
	
	func cancelPending() {
		guard !tasks.isEmpty else { return }
		
		if lock.lock(before: Date.distantFuture) {
#if DEBUG
			print("Trying to cancel pending task")
#endif
			tasks.first?.cancel()
			
			lock.unlock()
			
			dequeue()
		}
	}
	
	func cancelAll() {
		guard !tasks.isEmpty else { return }
		
		if lock.lock(before: Date.distantFuture) {
			for task in tasks {
				task.cancel()
			}
			
			tasks.removeAll()
			
			lock.unlock()
		}
	}
	
	private func checkServerIsReachable() -> Error? {
		// As odd as it may seem, we can't create the Reachability object only once
		// see https://github.com/ashleymills/Reachability.swift/issues/212
		do {
			let reachability = try Reachability(hostname: serviceString)
				
			switch reachability.connection {
			case .unavailable:
				return NSError(domain: Bundle.main.bundleIdentifier!,
				               code: Int(CFNetworkErrors.cfurlErrorNotConnectedToInternet.rawValue),
				               userInfo: [NSLocalizedDescriptionKey: "Internet Connection unavailable"])
			default:
				return nil
			}
		} catch {
			return error
		}
	}
	
	private func prepareBody(with parameters: [String: Any]) throws -> Data? {
#if DEBUG
		var options: JSONSerialization.WritingOptions	= [.prettyPrinted]
#else
		var options: JSONSerialization.WritingOptions	= []
#endif
		
		if #available(iOS 11, *) {
			options	= options.union(.sortedKeys)
		}
		return try JSONSerialization.data(withJSONObject: parameters, options: options)
	}
	
	private func prepareQuery(with parameters: [String: String]) -> String {
		var queryString	= ""
		
		for aKey in parameters.keys {
			if let paramValue = (parameters[aKey])?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
				if queryString.count > 1 {
					queryString.append("&")
				} else {
					queryString.append("?")
				}
				queryString.append("\(aKey)=\(paramValue)")
			}
		}
		
		return queryString
	}
	
	private func prepareMultiPart(with file: URL, boundary: String) throws -> Data {
		guard file.isFileURL else {
			throw NSError(domain: Bundle.main.bundleIdentifier!,
			              code: -1,
			              userInfo: [NSLocalizedDescriptionKey: "MultiPart POST: URL doesn't match a file"])
		}
		guard FileManager.default.fileExists(atPath: file.path, isDirectory: nil) else {
			throw NSError(domain: Bundle.main.bundleIdentifier!,
			              code: -2,
			              userInfo: [NSLocalizedDescriptionKey: "MultiPart POST: file not found"])
		}
		
		var data = Data()
		
		// Add the file data to the raw http request data
		data.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
		data.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(file.lastPathComponent)\"\r\n".data(using: .utf8)!)
		data.append("Content-Type: \(APIService.detectMIME(file.lastPathComponent))\r\n\r\n".data(using: .utf8)!)
		data.append(try Data(contentsOf: file, options: [.mappedIfSafe]))
		data.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
		
		return data
	}

	private func processResponse(data outData: inout Any?, response: URLResponse?, error outError: inout Error?, convert: Bool) {
		if let httpResponse = response as? HTTPURLResponse {
			if httpResponse.statusCode < 200 || httpResponse.statusCode > 399 {
				let serverMsg		= HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
				
				outError	= NSError(domain: Bundle.main.bundleIdentifier!,
				        	          code: httpResponse.statusCode,
				        	          userInfo: [NSLocalizedDescriptionKey: serverMsg])
				return
			}
		}
		
		if convert {
			do {
				var responseObject: Any?
				
				if let data = (outData as? Data), !data.isEmpty {
					responseObject	= try JSONSerialization.jsonObject(with: data, options: [.mutableContainers])
				}
				
				outData	= responseObject
			} catch {
				outError	= error
			}
		} else {
#if DEBUG
			if let data = (outData as? Data), !data.isEmpty {
				print("Response: \(String(data: data, encoding: .utf8) ?? "Invalid data")")
			}
#endif
		}
	}
	
	func upload(request: URLRequest, data fileData: Data, convert: Bool, completion: @escaping (Error?, Any?) -> Void) {
		let networkError = checkServerIsReachable()
		guard networkError == nil else {
			completion(networkError, nil)
			return
		}
		
		let task	= session.uploadTask(with: request, from: fileData) { data, response, error in
			var outData: Any?		= data
			var outError: Error?	= error

			self.processResponse(data: &outData, response: response, error: &outError, convert: convert)
			
			completion(outError, outData)
			self.dequeue()
		}
		
		if APIService.queueReqs {
			enqueue(task: task)
		} else {
			task.resume()
		}
	}
	
	func send(request: URLRequest, convert: Bool, completion: @escaping (Error?, Any?) -> Void) {
		let networkError = checkServerIsReachable()
		guard networkError == nil else {
			completion(networkError, nil)
			return
		}
		
		let task	= session.dataTask(with: request) { data, response, error in
			var outData: Any?		= data
			var outError: Error?	= error

			self.processResponse(data: &outData, response: response, error: &outError, convert: convert)
			
			completion(outError, outData)
			self.dequeue()
		}
		
		if APIService.queueReqs {
			enqueue(task: task)
		} else {
			task.resume()
		}
	}
	
	func get(endpoint: String, parameters: [String: String] = [:], convert: Bool = true, completion: @escaping (Error?, Any?) -> Void) {
		let queryString	= prepareQuery(with: parameters)
		var request		= URLRequest(url: URL(string: "\(urlProtocol)://\(serviceString)\(basePath)/\(endpoint)\(queryString)")!,
		           		             cachePolicy: .useProtocolCachePolicy,
		           		             timeoutInterval: timeout)
		
		request.httpMethod          = "GET"
		request.allHTTPHeaderFields = headers
		
		send(request: request, convert: convert, completion: completion)
	}
	
#if DEBUG
	func dumpBody(request: URLRequest) throws {
		let fm				= FileManager.default
		let documentDirURL	= fm.urls(for: .documentDirectory, in: .userDomainMask).last!
		
		try request.httpBody?.write(to: documentDirURL.appendingPathComponent("dump.txt"), options: [.noFileProtection, .atomicWrite])
	}
#endif
	
	func post(endpoint: String, query: [String: String]? = nil, parameters: [String: Any]? = nil, convert: Bool = true, completion: @escaping (Error?, Any?) -> Void) {
		do {
			let urlString: String!
			
			urlString	= "\(urlProtocol)://\(serviceString)\(basePath)/\(endpoint)"
			
			var postHeaders	= headers
			var request		= URLRequest(url: URL(string: urlString)!,
			           		             cachePolicy: .useProtocolCachePolicy,
			           		             timeoutInterval: timeout)
			
			request.httpMethod          = "POST"
			if parameters != nil {
				request.httpBody = try prepareBody(with: parameters!)
			} else if query != nil {
				let queryString	= prepareQuery(with: query!)
				let range		= queryString.index(queryString.startIndex, offsetBy: 1) ..< queryString.endIndex
				
				request.httpBody			= queryString[range].data(using: .utf8)
				postHeaders["Content-Type"]	= "application/x-www-form-urlencoded"
			}
			request.allHTTPHeaderFields = postHeaders

#if DEBUG
			if dumpPayload {
				try dumpBody(request: request)
				
				UIPasteboard.general.string	= String(data: request.httpBody!, encoding: .utf8)
			}
#endif
			
			send(request: request, convert: convert, completion: completion)
		} catch {
			completion(error, nil)
		}
	}
	
	func post(endpoint: String, file: URL, convert: Bool = true, completion: @escaping (Error?, Any?) -> Void) {
		do {
			var request = URLRequest(url: URL(string: "\(urlProtocol)://\(serviceString)\(basePath)/\(endpoint)")!,
			                         cachePolicy: .useProtocolCachePolicy,
			                         timeoutInterval: timeout)
			var postHeaders	= headers
			let boundary	= UUID().uuidString
			
			postHeaders["Content-Type"]	= "multipart/form-data; boundary=\(boundary)"
			request.httpMethod          = "POST"
			request.allHTTPHeaderFields = postHeaders
			
			let uploadData	= try prepareMultiPart(with: file, boundary: boundary)
			
			upload(request: request, data: uploadData, convert: convert, completion: completion)
		} catch {
			completion(error, nil)
		}
	}
	
	func put(endpoint: String, query: [String: String]? = nil, parameters: [String: Any]? = nil, convert: Bool = true, completion: @escaping (Error?, Any?) -> Void) {
		do {
			let urlString: String!
			
			if query != nil {
				urlString	= "\(urlProtocol)://\(serviceString)\(basePath)/\(endpoint)\(prepareQuery(with: query!))"
			} else {
				urlString	= "\(urlProtocol)://\(serviceString)\(basePath)/\(endpoint)"
			}
			
			var request = URLRequest(url: URL(string: urlString)!,
			                         cachePolicy: .useProtocolCachePolicy,
			                         timeoutInterval: timeout)
			
			request.httpMethod          = "PUT"
			request.allHTTPHeaderFields = headers
			if parameters != nil { request.httpBody = try prepareBody(with: parameters!) }
						
#if DEBUG
			if dumpPayload {
				try dumpBody(request: request)
				
				UIPasteboard.general.string	= String(data: request.httpBody!, encoding: .utf8)
			}
#endif

			send(request: request, convert: convert, completion: completion)
		} catch {
			completion(error, nil)
		}
	}
	
	func delete(endpoint: String, parameters: [String: String]? = nil, completion: @escaping (Error?, Any?) -> Void) {
		let urlString: String!
		
		if parameters != nil {
			urlString	= "\(urlProtocol)://\(serviceString)\(basePath)/\(endpoint)\(prepareQuery(with: parameters!))"
		} else {
			urlString	= "\(urlProtocol)://\(serviceString)\(basePath)/\(endpoint)"
		}
		
		var request		= URLRequest(url: URL(string: urlString)!,
		           		             cachePolicy: .useProtocolCachePolicy,
		           		             timeoutInterval: timeout)
		
		request.httpMethod          = "DELETE"
		request.allHTTPHeaderFields = headers
		
		send(request: request, convert: false, completion: completion)
	}

	class func detectMIME(_ fileRef: String) -> String {
		let fileExt		= (fileRef as NSString).pathExtension.lowercased()
		
		switch fileExt {
		// Images
		case "jpg":
			return "image/jpeg"
		case "png":
			return	"image/png"
			
		// Audio
		case "m4a":
			return	"audio/mp4"
			
		// Video
		case "m4v", "mp4":
			return	"video/mp4"
		case "mov":
			return "video/quicktime"
			
		// Others
		case "txt":
			return "text/plain"
		case "csv":
			return "text/csv"
		case "tsv", "tab":
			return "text/tab-separated-values"
		case "json":
			return "application/json"
		case "zip":
			return "application/zip"
		default:
			return "application/octet-stream"
		}
	}
}

/* See:
 https://www.bugsee.com/blog/ssl-certificate-pinning-in-mobile-applications/
 https://stackoverflow.com/questions/34223291/ios-certificate-pinning-with-swift-and-nsurlsession
 https://stackoverflow.com/questions/25388747/sha256-in-swift
 */
class CloudSSLPinning: NSObject, URLSessionDelegate {
	static let rsa2048Asn1Header: [UInt8] = [
		0x30, 0x82, 0x01, 0x22, 0x30, 0x0D, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86,
		0xF7, 0x0D, 0x01, 0x01, 0x01, 0x05, 0x00, 0x03, 0x82, 0x01, 0x0F, 0x00
	]
	
	private func sha256(data: Data) -> String {
		var keyWithHeader = Data(CloudSSLPinning.rsa2048Asn1Header)
		keyWithHeader.append(data)
		
		var hash = [UInt8](repeating: 0,  count: Int(CC_SHA256_DIGEST_LENGTH))
		
		keyWithHeader.withUnsafeBytes { buffer in
			_ = CC_SHA256(buffer.baseAddress, CC_LONG(keyWithHeader.count), &hash)
		}
		
		return Data(hash).base64EncodedString()
	}
	
	func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Swift.Void) {
		if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
			if let serverTrust = challenge.protectionSpace.serverTrust {
				// We don't really care about the error type we get, only if it's successful
				var status: OSStatus	= errSecUnimplemented
				
				if #available(iOS 13.0, *) {
					if SecTrustEvaluateWithError(serverTrust, nil) {
						status	= errSecSuccess
					}
				} else {
					var secresult = SecTrustResultType.invalid
					
					status = SecTrustEvaluate(serverTrust, &secresult)
				}
				
				if errSecSuccess == status {
#if DEBUG
					print(SecTrustGetCertificateCount(serverTrust))
#endif
					if let serverCertificate = SecTrustGetCertificateAtIndex(serverTrust, 0) {
						// Certificate pinning, uncomment to use this instead of public key pinning
						// This is less reliable if  certificate changes often
//						let serverCertificateData:NSData = SecCertificateCopyData(serverCertificate)
//						let certHash = sha256(data: serverCertificateData as Data)
//						if (certHash == apiCertificateHash) {
//							// Success! This is our server
//							completionHandler(.useCredential, URLCredential(trust:serverTrust))
//							return
//						}
						
						let serverPublicKey: SecKey?
						
						// Public key pinning
						if #available(iOS 12.0, *) {
							serverPublicKey = SecCertificateCopyKey(serverCertificate)
						} else {
							serverPublicKey = SecCertificateCopyPublicKey(serverCertificate)
						}
						if serverPublicKey != nil {
							let serverPublicKeyData: NSData = SecKeyCopyExternalRepresentation(serverPublicKey!, nil)!
							let keyHash = sha256(data: serverPublicKeyData as Data)
							if keyHash == apiPublicKeyHash {
								// Success! This is our server
								completionHandler(.useCredential, URLCredential(trust: serverTrust))
								return
							}
						}
					}
				}
			}
		}
		
		// Pinning failed
		completionHandler(.cancelAuthenticationChallenge, nil)
	}
}
