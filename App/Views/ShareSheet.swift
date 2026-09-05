import SwiftUI
import UIKit

/// Thin `UIActivityViewController` wrapper for handing an exported file to the
/// system share sheet — Files, AirDrop, Mail, and the rest. Presented with
/// `.sheet`; `items` is normally a single file `URL` written to the temp
/// directory by the caller so the sheet shows a real name and type.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
