//
//  TextRecognizer.swift
//  GigGrow
//
//  On-device OCR over a screenshot.
//
//  Vision runs entirely on the phone: no network call, no API key, no vendor.
//  That matters beyond convenience — the privacy sheet promises nothing leaves
//  the device, and a screenshot of someone's earnings is about as sensitive as
//  this app gets. Sending it to a server to be read would make that promise
//  false.
//

import Foundation
import Vision
import CoreGraphics

// MARK: - Line

/// One recognised line, with where it sat on the image.
struct RecognisedLine: Equatable {
    let text: String
    /// Vision's confidence, 0…1.
    let confidence: Float
    /// Normalised bounding box, origin bottom-left as Vision reports it.
    let box: CGRect

    /// Vertical position with the origin flipped to the top, which is how
    /// people describe a screenshot: "the total is near the top".
    var topDownY: CGFloat { 1 - box.maxY }
}

// MARK: - Recogniser

enum TextRecognizer {

    enum Failure: LocalizedError {
        case unreadableImage
        case visionFailed(String)

        var errorDescription: String? {
            switch self {
            case .unreadableImage:
                return "That image couldn't be read. Try a PNG or JPEG screenshot."
            case .visionFailed(let detail):
                return "Text recognition failed: \(detail)"
            }
        }
    }

    /// Reads every line of text in the image, top to bottom.
    static func recognise(in image: CGImage) throws -> [RecognisedLine] {
        let request = VNRecognizeTextRequest()

        // Accurate over fast: this runs once, on a still image, and a
        // misread digit is a wrong number in someone's tax set-aside.
        request.recognitionLevel = .accurate

        // Language correction "fixes" figures and app names into words —
        // exactly the opposite of what a screenshot of numbers needs.
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw Failure.visionFailed(error.localizedDescription)
        }

        let observations = request.results ?? []
        return observations
            .compactMap { observation -> RecognisedLine? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                return RecognisedLine(
                    text: candidate.string,
                    confidence: candidate.confidence,
                    box: observation.boundingBox
                )
            }
            // Reading order, so "Total" and the figure under it stay adjacent.
            .sorted { $0.topDownY < $1.topDownY }
    }
}
