import SwiftUI

struct StepperInput: View {
    @Binding var valueStr: String
    let increment: Double
    let minimum: Double
    let placeholder: Double
    var isInteger: Bool = false
    var isDisabled: Bool = false
    var autoFocus: Bool = false

    @FocusState private var isManualFocused: Bool
    @State private var holdTask: Task<Void, Never>? = nil
    @GestureState private var minusHeld = false
    @GestureState private var plusHeld = false

    private var currentValue: Double {
        valueStr.isEmpty
            ? placeholder
            : Double(valueStr.replacingOccurrences(of: ",", with: ".")) ?? placeholder
    }

    private var displayText: String {
        guard !valueStr.isEmpty else { return "" }
        return isInteger ? "\(Int(currentValue))" : formatted(currentValue)
    }

    private var placeholderText: String {
        isInteger ? "\(Int(placeholder))" : formatted(placeholder)
    }

    private func formatted(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(v))" : String(format: "%.1f", v)
    }

    var body: some View {
        HStack(spacing: 0) {
            stepIcon(systemName: "minus", isHeld: minusHeld)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .updating($minusHeld) { _, state, _ in state = true }
                        .onChanged { _ in startHold(-1) }
                        .onEnded   { _ in stopHold() }
                )
                .disabled(isDisabled)

            ZStack {
                Text(valueStr.isEmpty ? placeholderText : displayText)
                    .font(.appTitle)
                    .foregroundColor(valueStr.isEmpty ? .gray.opacity(0.35) : .white)
                    .frame(minWidth: 52, alignment: .center)
                    .allowsHitTesting(false)

                TextField("", text: $valueStr)
                    .keyboardType(isInteger ? .numberPad : .decimalPad)
                    .focused($isManualFocused)
                    .opacity(0.01)
                    .frame(minWidth: 52)
                    .disabled(isDisabled)
                    .multilineTextAlignment(.center)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard !isDisabled else { return }
                isManualFocused = true
            }

            stepIcon(systemName: "plus", isHeld: plusHeld)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .updating($plusHeld) { _, state, _ in state = true }
                        .onChanged { _ in startHold(1) }
                        .onEnded   { _ in stopHold() }
                )
                .disabled(isDisabled)
        }
        .background(Color.appSurfaceInset)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.09), lineWidth: 1))
        .onChange(of: isManualFocused) { _, focused in
            if !focused { validateInput() }
        }
        .onAppear {
            guard autoFocus else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                isManualFocused = true
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if isManualFocused {
                    Spacer()
                    Button("Terminé") { isManualFocused = false }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color.forge)
                }
            }
        }
    }

    @ViewBuilder
    private func stepIcon(systemName: String, isHeld: Bool) -> some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(isDisabled ? 0 : (isHeld ? 0.1 : 0.04)))
                .frame(width: 32, height: 32)
            Image(systemName: systemName)
                .font(.appBody.weight(.semibold))
                .foregroundColor(isDisabled ? .gray.opacity(0.2) : .white.opacity(isHeld ? 1.0 : 0.9))
        }
        .frame(width: 44, height: 44)
        .scaleEffect(isHeld ? 0.82 : 1.0)
        .animation(.easeInOut(duration: 0.08), value: isHeld)
        .contentShape(Rectangle())
    }

    private func startHold(_ direction: Int) {
        guard holdTask == nil else { return }
        step(direction)
        holdTask = Task {
            // 400ms avant le début du rapid-fire
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            let loopStart = Date()
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(loopStart)
                let ns: UInt64 = elapsed < 1.0 ? 200_000_000   // 200ms — lent
                               : elapsed < 2.5 ? 80_000_000    //  80ms — moyen
                               :                 30_000_000    //  30ms — rapide (~83 lbs/s)
                try? await Task.sleep(nanoseconds: ns)
                guard !Task.isCancelled else { return }
                await MainActor.run { step(direction) }
            }
        }
    }

    private func stopHold() {
        holdTask?.cancel()
        holdTask = nil
    }

    private func step(_ direction: Int) {
        let newVal = max(minimum, currentValue + Double(direction) * increment)
        apply(newVal)
        triggerImpact(style: .light)
    }

    private func apply(_ val: Double) {
        let clamped = max(minimum, val)
        valueStr = isInteger ? "\(Int(clamped))" : formatted(clamped)
    }

    private func validateInput() {
        guard !valueStr.isEmpty else { return }
        let v = Double(valueStr.replacingOccurrences(of: ",", with: ".")) ?? minimum
        apply(v)
    }
}
