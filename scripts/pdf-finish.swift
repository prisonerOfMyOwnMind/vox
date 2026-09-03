// Проставляет номера страниц и отрисовывает каждую страницу в PNG.
//
// Chrome печатает свой колонтитул с локальным путём к файлу — в публичный
// документ он попасть не должен, поэтому печать идёт с --no-pdf-header-footer,
// а нумерация проставляется здесь. Растеризация нужна, чтобы глазами проверить
// русский текст, переносы, таблицы и сами номера.
//
// Запуск: swift scripts/pdf-finish.swift вход.pdf выход.pdf каталог-картинок

import AppKit
import CoreText
import Foundation
import PDFKit

let args = CommandLine.arguments
guard args.count == 4 else {
    FileHandle.standardError.write(Data("нужно: вход.pdf выход.pdf каталог-картинок\n".utf8))
    exit(2)
}
let inputURL = URL(fileURLWithPath: args[1])
let outputURL = URL(fileURLWithPath: args[2])
let imagesURL = URL(fileURLWithPath: args[3])

guard let document = PDFDocument(url: inputURL), document.pageCount > 0 else {
    FileHandle.standardError.write(Data("не удалось прочитать \(inputURL.path)\n".utf8))
    exit(1)
}
try? FileManager.default.createDirectory(at: imagesURL, withIntermediateDirectories: true)

// --- номера страниц ---
guard let consumer = CGDataConsumer(url: outputURL as CFURL) else { exit(1) }
var firstBox = document.page(at: 0)!.bounds(for: .mediaBox)
guard let context = CGContext(consumer: consumer, mediaBox: &firstBox, nil) else { exit(1) }

let font = CTFontCreateWithName("HelveticaNeue" as CFString, 8.5, nil)
let inkColor = NSColor(calibratedWhite: 0.45, alpha: 1).cgColor

for index in 0..<document.pageCount {
    guard let page = document.page(at: index) else { continue }
    var box = page.bounds(for: .mediaBox)
    context.beginPage(mediaBox: &box)
    context.saveGState()
    page.draw(with: .mediaBox, to: context)
    context.restoreGState()

    let label = "\(index + 1)"
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font, .foregroundColor: inkColor,
    ]
    let line = CTLineCreateWithAttributedString(
        NSAttributedString(string: label, attributes: attributes))
    let width = CTLineGetTypographicBounds(line, nil, nil, nil)
    context.textPosition = CGPoint(x: box.midX - CGFloat(width) / 2, y: box.minY + 34)
    CTLineDraw(line, context)

    context.endPage()
}
context.closePDF()

// --- картинки для визуальной проверки ---
guard let finished = PDFDocument(url: outputURL) else { exit(1) }
let scale: CGFloat = 2.0
for index in 0..<finished.pageCount {
    guard let page = finished.page(at: index) else { continue }
    let box = page.bounds(for: .mediaBox)
    let pixels = NSSize(width: box.width * scale, height: box.height * scale)
    let image = NSImage(size: pixels)
    image.lockFocus()
    NSColor.white.setFill()
    NSRect(origin: .zero, size: pixels).fill()
    if let ctx = NSGraphicsContext.current?.cgContext {
        ctx.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: ctx)
    }
    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { continue }
    let name = String(format: "page-%02d.png", index + 1)
    try png.write(to: imagesURL.appendingPathComponent(name))
}

print("страниц: \(finished.pageCount), PDF: \(outputURL.path), картинки: \(imagesURL.path)")
