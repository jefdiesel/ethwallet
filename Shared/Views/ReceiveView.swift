import SwiftUI
#if canImport(CoreImage)
import CoreImage.CIFilterBuiltins
#endif

/// View for displaying receive address and QR code
struct ReceiveView: View {
    let account: Account?
    @Environment(\.dismiss) private var dismiss

    @State private var copied = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // QR Code
                if let account = account {
                    qrCodeView(for: account.address)
                        .frame(width: 200, height: 200)
                        .padding()
                        .background(Color.white)
                        .cornerRadius(16)
                        .shadow(radius: 4)
                }

                // Address display
                VStack(spacing: 8) {
                    Text("Your Address")
                        .font(.headline)

                    if let address = account?.address {
                        Text(address)
                            .font(.body.monospaced())
                            .multilineTextAlignment(.center)
                            .textSelection(.enabled)
                            .padding()
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(8)
                    }
                }

                // Copy button
                Button {
                    copyAddress()
                } label: {
                    Label(
                        copied ? "Copied!" : "Copy Address",
                        systemImage: copied ? "checkmark" : "doc.on.doc"
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(account == nil)

                // Share button
                #if os(iOS)
                if let address = account?.address {
                    ShareLink(item: address) {
                        Label("Share Address", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                }
                #endif

                Spacer()

                // Warning
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)

                    Text("Only send ETH or EVM-compatible tokens to this address")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }
            .padding()
            .navigationTitle("Receive")
            #if os(macOS)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            #endif
        }
        .frame(minWidth: 350, minHeight: 500)
    }

    @ViewBuilder
    private func qrCodeView(for address: String) -> some View {
        #if canImport(CoreImage)
        if let qrImage = generateQRCode(from: address) {
            Image(qrImage, scale: 1, label: Text("QR Code"))
                .interpolation(.none)
                .resizable()
                .scaledToFit()
        } else {
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .overlay {
                    Text("QR Code")
                        .foregroundStyle(.secondary)
                }
        }
        #else
        Rectangle()
            .fill(Color.secondary.opacity(0.2))
            .overlay {
                Text("QR Code")
                    .foregroundStyle(.secondary)
            }
        #endif
    }

    #if canImport(CoreImage)
    private func generateQRCode(from string: String) -> CGImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()

        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let ciImage = filter.outputImage else { return nil }

        // Scale up the QR code
        let scale = 10.0
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        let scaledImage = ciImage.transformed(by: transform)

        return context.createCGImage(scaledImage, from: scaledImage.extent)
    }
    #endif

    private func copyAddress() {
        guard let address = account?.address else { return }

        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(address, forType: .string)
        #else
        UIPasteboard.general.string = address
        #endif

        withAnimation {
            copied = true
        }

        // Reset after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                copied = false
            }
        }
    }
}

// MARK: - Address Card View

struct AddressCardView: View {
    let account: Account

    var body: some View {
        VStack(spacing: 12) {
            // Account label
            Text(account.label)
                .font(.headline)

            // Address
            Text(account.address)
                .font(.caption.monospaced())
                .multilineTextAlignment(.center)
                .padding(8)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(4)

            // Derivation path
            Text(account.derivationPath)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(12)
    }
}

#Preview {
    ReceiveView(
        account: Account(index: 0, address: "0x1234567890abcdef1234567890abcdef12345678")
    )
}
