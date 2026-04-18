import SwiftUI
import Combine

// MARK: - 1. Moteur de Particules Avancé (Débris Irréguliers)
struct AdvancedShard: Identifiable {
    let id = UUID()
    var position: CGPoint
    var velocity: CGSize
    var rotation: Double
    var size: CGFloat
    var opacity: Double
    var color: Color
    var type: Int // 0: Triangle, 1: Éclat
}

// MARK: - 2. SplashView Cinématique
struct SplashView: View {
    @State private var logoScale: CGFloat = 0.8
    @State private var logoOpacity: Double = 0
    @State private var particles: [AdvancedShard] = []
    @State private var shatterTriggered = false
    @State private var allOpacity: Double = 1
    
    // Pour l'effet de tremblement (Shake)
    @State private var screenShake: CGFloat = 0
    
    // Constantes
    let tagline = "DO MORE"
    let timer = Timer.publish(every: 0.016, on: .main, in: .common).autoconnect() // ~60 FPS
    var onFinish: () -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // FOND : Noir absolu
                Color.black.ignoresSafeArea()

                // 1. LE LOGO (Intégré et réactif)
                Image("SplashImage")
                    .resizable()
                    .scaledToFit()
                    .frame(width: geo.size.width * 0.7) // Prend 70% de la largeur
                    .opacity(logoOpacity)
                    .scaleEffect(shatterTriggered ? 1.05 : logoScale) // S'agrandit à l'impact
                    .blur(radius: (1 - logoOpacity) * 10)
                    .ignoresSafeArea()
                    .animation(.spring(response: 0.6, dampingFraction: 0.6).delay(1.5), value: shatterTriggered) // Réactif à shatterTriggered

                // 2. MOTEUR DE PARTICULES (Canvas pour débris irréguliers)
                Canvas { context, size in
                    for shard in particles {
                        var innerContext = context
                        innerContext.opacity = shard.opacity
                        innerContext.translateBy(x: shard.position.x, y: shard.position.y)
                        innerContext.rotate(by: .degrees(shard.rotation))
                        innerContext.scaleBy(x: shard.size / 10, y: shard.size / 10)
                        
                        // Dessiner l'éclat (Triangle ou forme brisée)
                        let path = Path { p in
                            if shard.type == 0 { // Triangle
                                p.move(to: CGPoint(x: 0, y: 0))
                                p.addLine(to: CGPoint(x: 10, y: 2))
                                p.addLine(to: CGPoint(x: 5, y: 10))
                            } else { // Éclat irrégulier
                                p.move(to: CGPoint(x: 0, y: 3))
                                p.addLine(to: CGPoint(x: 10, y: 0))
                                p.addLine(to: CGPoint(x: 8, y: 10))
                                p.addLine(to: CGPoint(x: 2, y: 8))
                            }
                            p.closeSubpath()
                        }
                        innerContext.fill(path, with: .color(shard.color))
                    }
                }
                .blendMode(.plusLighter) // Fait briller les particules

                // 3. LE TEXTE "DO MORE" (LOOK INDUSTRIEL)
                VStack {
                    Spacer()
                    HStack(spacing: -2) { // Espacement négatif pour un look compact et massif
                        ForEach(Array(tagline.enumerated()), id: \.offset) { index, letter in
                            ZStack {
                                // COUCHE 1 : La structure (Gris très sombre pour la profondeur)
                                Text(String(letter))
                                    .font(.system(size: geo.size.width * 0.2, weight: .black))
                                    .foregroundColor(Color(white: 0.1))
                                    .offset(x: 2, y: 2)

                                // COUCHE 2 : Le métal (Le dégradé orange/cuivre)
                                Text(String(letter))
                                    .font(.system(size: geo.size.width * 0.2, weight: .black))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [
                                                Color(hex: "FFCC00"), // Or brillant
                                                Color(hex: "E65100"), // Orange brûlé
                                                Color(hex: "311B92").opacity(0.8) // Touche de bleu nuit pour le contraste métal
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                
                                // COUCHE 3 : Les cicatrices (Fissures noires)
                                if shatterTriggered {
                                    Text(String(letter))
                                        .font(.system(size: geo.size.width * 0.2, weight: .black))
                                        .foregroundStyle(.black)
                                        .mask(
                                            ZStack {
                                                // On crée des "entailles" diagonales
                                                Rectangle()
                                                    .rotation(.degrees(35))
                                                    .frame(width: 3, height: 200)
                                                    .offset(x: -15)
                                                
                                                Rectangle()
                                                    .rotation(.degrees(-40))
                                                    .frame(width: 2, height: 200)
                                                    .offset(x: 10)
                                            }
                                        )
                                }
                            }
                            // Animation de "reconstruction" agressive
                            .opacity(shatterTriggered ? 1 : 0)
                            .scaleEffect(shatterTriggered ? 1 : 2.5) // Arrive de "devant" l'écran
                            .rotation3DEffect(.degrees(shatterTriggered ? 0 : -45), axis: (x: 1, y: 0.2, z: 0))
                            .animation(.interpolatingSpring(stiffness: 120, damping: 12).delay(Double(index) * 0.06), value: shatterTriggered)
                        }
                    }
                    .offset(x: screenShake)
                    Spacer().frame(height: geo.size.height * 0.12)
                }
            }
        }
        .opacity(allOpacity)
        .ignoresSafeArea()
        .onReceive(timer) { _ in updateParticles() }
        .onAppear(perform: startSequence)
    }

    // MARK: - Logique Cinématique (Animations & Physique)
    private func startSequence() {
        // Apparition du logo (sans parallaxe)
        withAnimation(.easeOut(duration: 1.5)) {
            logoOpacity = 1
            logoScale = 1.0 // S'agrandit doucement
        }

        // L'Impact (Cinématique)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            // Impact haptique lourd
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.impactOccurred()
            
            // Trigger effets visuels
            shatterTriggered = true
            createAdvancedExplosion()
            
            // Effet de tremblement (Shake)
            withAnimation(.default.repeatCount(4, autoreverses: true)) {
                screenShake = 6
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                screenShake = 0
            }
        }

        // Finalisation
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
            withAnimation(.easeOut(duration: 0.5)) { allOpacity = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { onFinish() }
        }
    }

    private func createAdvancedExplosion() {
        for _ in 0..<80 {
            let color = Bool.random() ? Color.orange : Color(hex: "FFCC00")
            let shard = AdvancedShard(
                position: CGPoint(x: UIScreen.main.bounds.midX, y: UIScreen.main.bounds.midY + 150),
                velocity: CGSize(width: .random(in: -18...18), height: .random(in: -25...10)), // Plus rapide
                rotation: .random(in: 0...360),
                size: .random(in: 3...12),
                opacity: 1.0,
                color: color,
                type: Int.random(in: 0...1)
            )
            particles.append(shard)
        }
    }

    private func updateParticles() {
        for i in particles.indices {
            particles[i].position.x += particles[i].velocity.width
            particles[i].position.y += particles[i].velocity.height
            particles[i].velocity.height += 0.4 // Gravité plus forte
            particles[i].rotation += particles[i].velocity.width * 2
            particles[i].opacity -= 0.01
        }
        particles.removeAll { $0.opacity <= 0 }
    }
}
