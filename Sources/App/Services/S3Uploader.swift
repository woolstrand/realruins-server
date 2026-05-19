//
//  S3Uploader.swift
//  App
//
//  Minimal AWS Signature Version 4 S3-compatible uploader.
//  Used with DigitalOcean Spaces (path-style: host/bucket/key).
//

import Foundation
import Vapor
import Crypto

struct S3Uploader {
    let accessKey: String
    let secretKey: String
    let bucket: String
    let host: String
    let region: String

    // Upload `data` as `<fileName>.bp` using path-style addressing.
    func upload(client: Client, data: ByteBuffer, fileName: String, logger: Logger) async throws {
        let key = "\(fileName).bp"
        let path = "/\(bucket)/\(key)"
        let urlString = "https://\(host)\(path)"

        logger.notice("S3 upload starting: PUT \(urlString) (\(data.readableBytes) bytes)")

        let now = Date()
        let amzDate = amzDateString(now)
        let dateStamp = dateStampString(now)

        let contentType = "application/octet-stream"
        let dataBytes = Array(data.readableBytesView)
        let payloadHash = sha256Hex(dataBytes)

        // Canonical headers must be sorted alphabetically.
        let canonicalHeaders =
            "content-type:\(contentType)\n" +
            "host:\(host)\n" +
            "x-amz-acl:public-read\n" +
            "x-amz-content-sha256:\(payloadHash)\n" +
            "x-amz-date:\(amzDate)\n"
        let signedHeaders = "content-type;host;x-amz-acl;x-amz-content-sha256;x-amz-date"

        let canonicalRequest =
            "PUT\n" +
            "\(path)\n" +
            "\n" +
            "\(canonicalHeaders)\n" +
            "\(signedHeaders)\n" +
            "\(payloadHash)"

        let credentialScope = "\(dateStamp)/\(region)/s3/aws4_request"
        let stringToSign =
            "AWS4-HMAC-SHA256\n" +
            "\(amzDate)\n" +
            "\(credentialScope)\n" +
            sha256Hex(Array(canonicalRequest.utf8))

        let signingKey = deriveSigningKey(
            secretKey: secretKey,
            dateStamp: dateStamp,
            region: region,
            service: "s3"
        )
        let signature = hmacSHA256Hex(key: signingKey, data: Array(stringToSign.utf8))

        let authorization =
            "AWS4-HMAC-SHA256 " +
            "Credential=\(accessKey)/\(credentialScope), " +
            "SignedHeaders=\(signedHeaders), " +
            "Signature=\(signature)"

        var headers = HTTPHeaders()
        headers.add(name: "Authorization", value: authorization)
        headers.add(name: "x-amz-date", value: amzDate)
        headers.add(name: "x-amz-content-sha256", value: payloadHash)
        headers.add(name: "x-amz-acl", value: "public-read")
        headers.add(name: "Content-Type", value: contentType)

        var request = ClientRequest(method: .PUT, url: URI(string: urlString), headers: headers, body: nil)
        request.body = data

        let response = try await client.send(request)
        let statusCode = response.status.code
        let responseBody = response.body.map { String(buffer: $0) } ?? ""

        guard statusCode / 100 == 2 else {
            logger.error("S3 upload failed: HTTP \(statusCode) from \(urlString) — body: \(responseBody)")
            throw Abort(.internalServerError, reason: "S3 upload failed with HTTP \(statusCode)")
        }

        logger.notice("S3 upload succeeded: HTTP \(statusCode) for \(urlString)")
    }

    // MARK: - AWS Sig V4 helpers

    private func sha256Hex(_ bytes: [UInt8]) -> String {
        hexString(SHA256.hash(data: bytes))
    }

    private func hmacSHA256(_ key: SymmetricKey, _ data: [UInt8]) -> [UInt8] {
        Array(HMAC<SHA256>.authenticationCode(for: data, using: key))
    }

    private func hmacSHA256Hex(key: SymmetricKey, data: [UInt8]) -> String {
        hexString(HMAC<SHA256>.authenticationCode(for: data, using: key))
    }

    private func hexString(_ sequence: some Sequence<UInt8>) -> String {
        sequence.map { String(format: "%02x", $0) }.joined()
    }

    private func deriveSigningKey(secretKey: String, dateStamp: String, region: String, service: String) -> SymmetricKey {
        let initial = SymmetricKey(data: Array("AWS4\(secretKey)".utf8))
        let dateKey  = hmacSHA256(initial, Array(dateStamp.utf8))
        let regionKey  = hmacSHA256(SymmetricKey(data: dateKey), Array(region.utf8))
        let serviceKey = hmacSHA256(SymmetricKey(data: regionKey), Array(service.utf8))
        let signingKey = hmacSHA256(SymmetricKey(data: serviceKey), Array("aws4_request".utf8))
        return SymmetricKey(data: signingKey)
    }

    private func amzDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    private func dateStampString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
}

// MARK: - Application storage extension

extension Application {
    private struct S3UploaderKey: StorageKey {
        typealias Value = S3Uploader
    }

    var s3Uploader: S3Uploader {
        get {
            guard let uploader = storage[S3UploaderKey.self] else {
                fatalError("S3Uploader not configured. Call app.s3Uploader = ... in configure.swift")
            }
            return uploader
        }
        set { storage[S3UploaderKey.self] = newValue }
    }
}

extension Request {
    var s3Uploader: S3Uploader { application.s3Uploader }
}
