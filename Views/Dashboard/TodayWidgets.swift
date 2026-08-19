import SwiftUI

// MARK: - Day Actions Row

struct DayActionsRow: View {
    let sessionLogged: Bool
    let moodDone: Bool
    let nutritionLogged: Bool
    var onSessionTap: () -> Void
    var onMoodTap: () -> Void
    var onNutritionTap: () -> Void

    private var allDone: Bool { sessionLogged && moodDone && nutritionLogged }

    var body: some View {
        if !allDone {
            HStack(spacing: 8) {
                if !sessionLogged {
                    ActionChip(icon: "dumbbell.fill", label: "Séance", color: Color.forge, action: onSessionTap)
                }
                if !moodDone {
                    ActionChip(icon: "brain.head.profile", label: "Humeur", color: Color.statusYellow, action: onMoodTap)
                }
                if !nutritionLogged {
                    ActionChip(icon: "fork.knife", label: "Repas", color: Color.statusGreen, action: onNutritionTap)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

private struct ActionChip: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.appLabel.weight(.semibold))
                    .foregroundColor(color)
                Text(label)
                    .font(.appCaption.weight(.semibold))
                    .foregroundColor(.appTextPrimary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(color.opacity(0.10))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(color.opacity(0.25), lineWidth: 1))
            .cornerRadius(22)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Quote Card

struct QuoteCard: View {
    private let quote = QuoteData.today()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "quote.opening")
                    .font(.appCaption)
                    .foregroundColor(.statusPurple.opacity(0.8))
                Text("PENSÉE DU JOUR")
                    .font(.appCaption).fontWeight(.semibold)
                    .foregroundColor(.statusPurple.opacity(0.8))
                    .tracking(0.8)
            }
            Text(quote.text)
                .font(.appBody)
                .italic()
                .foregroundColor(.appTextPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Text("— \(quote.author) · \(quote.context)")
                .font(.appCaption)
                .foregroundColor(Color(white: 0.55))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appCard)
        .cornerRadius(14)
    }
}

// MARK: - Quotes Data

struct DailyQuote {
    let text: String
    let author: String
    let context: String
}

enum QuoteData {
    static func today() -> DailyQuote {
        let tz = TimeZone.current.secondsFromGMT()
        let dayIndex = (Int(Date().timeIntervalSince1970) + tz) / 86400
        return allQuotes[((dayIndex % allQuotes.count) + allQuotes.count) % allQuotes.count]
    }

    static let allQuotes: [DailyQuote] = [
        // Marc Aurèle
        .init(text: "You have power over your mind, not outside events. Realize this, and you will find strength.",
              author: "Marc Aurèle", context: "Méditations, ~170 AD"),
        .init(text: "Waste no more time arguing about what a good man should be. Be one.",
              author: "Marc Aurèle", context: "Méditations"),
        .init(text: "The impediment to action advances action. What stands in the way becomes the way.",
              author: "Marc Aurèle", context: "Méditations"),
        .init(text: "If it is not right, do not do it; if it is not true, do not say it.",
              author: "Marc Aurèle", context: "Méditations"),
        .init(text: "Confine yourself to the present.",
              author: "Marc Aurèle", context: "Méditations"),
        .init(text: "Never esteem anything as of advantage if it will make you break your word or lose your self-respect.",
              author: "Marc Aurèle", context: "Méditations"),
        .init(text: "The first rule is to keep an untroubled spirit. The second is to look things in the face and know them for what they are.",
              author: "Marc Aurèle", context: "Méditations"),
        .init(text: "You could leave life right now. Let that determine what you do and say and think.",
              author: "Marc Aurèle", context: "Méditations"),
        // Sénèque
        .init(text: "Begin at once to live, and count each separate day as a separate life.",
              author: "Sénèque", context: "Lettres à Lucilius, 65 AD"),
        .init(text: "Luck is what happens when preparation meets opportunity.",
              author: "Sénèque", context: "Lettres à Lucilius"),
        .init(text: "It is not that things are difficult that we do not dare, it is because we do not dare that they are difficult.",
              author: "Sénèque", context: "Lettres à Lucilius"),
        .init(text: "Omnia aliena sunt, tempus tantum nostrum est.",
              author: "Sénèque", context: "«Tout est étranger ; seul le temps est nôtre.» — Lettres à Lucilius"),
        // Épictète
        .init(text: "No man is free who is not master of himself.",
              author: "Épictète", context: "Discours"),
        .init(text: "Make the best use of what is in your power, and take the rest as it happens.",
              author: "Épictète", context: "Enchiridion"),
        .init(text: "First say to yourself what you would be, then do what you have to do.",
              author: "Épictète", context: "Discours III.23"),
        // Kobe Bryant
        .init(text: "The most important thing is to try and inspire people so that they can be great in whatever they want to do.",
              author: "Kobe Bryant", context: "Interview, 2018"),
        .init(text: "Everything negative — pressure, challenges — is all an opportunity for me to rise.",
              author: "Kobe Bryant", context: "The Mamba Mentality"),
        .init(text: "If you're afraid to fail, then you're probably going to fail.",
              author: "Kobe Bryant", context: "The Mamba Mentality"),
        .init(text: "The best competition I have is against myself, to become better.",
              author: "Kobe Bryant", context: "The Mamba Mentality"),
        .init(text: "I have self-doubt. I have insecurity. I have fear of failure. But I don't let it stop me.",
              author: "Kobe Bryant", context: "The Mamba Mentality"),
        // Michael Jordan
        .init(text: "I've failed over and over and over again in my life. And that is why I succeed.",
              author: "Michael Jordan", context: "Nike, 1997"),
        .init(text: "I can accept failure. Everyone fails at something. But I can't accept not trying.",
              author: "Michael Jordan", context: "I Can't Accept Not Trying, 1994"),
        .init(text: "Talent wins games, but teamwork and intelligence win championships.",
              author: "Michael Jordan", context: "I Can't Accept Not Trying"),
        .init(text: "You have to expect things of yourself before you can do them.",
              author: "Michael Jordan", context: "Attribué"),
        // Muhammad Ali
        .init(text: "I hated every minute of training, but I said: don't quit. Suffer now and live the rest of your life as a champion.",
              author: "Muhammad Ali", context: "Biographie"),
        .init(text: "Champions aren't made in gyms. Champions are made from something they have deep inside them — a desire, a dream, a vision.",
              author: "Muhammad Ali", context: "Interview"),
        .init(text: "Float like a butterfly, sting like a bee. His hands can't hit what his eyes can't see.",
              author: "Muhammad Ali", context: "Avant le combat Liston, 1964"),
        .init(text: "Impossible is just a big word thrown around by small men who find it easier to live in the world they've been given than to explore the power they have to change it.",
              author: "Muhammad Ali", context: "Adidas, 2004"),
        // David Goggins
        .init(text: "You are in danger of living a life so comfortable and so soft that you will die without ever realizing your true potential.",
              author: "David Goggins", context: "Can't Hurt Me, 2018"),
        .init(text: "The most important conversations you'll ever have are the ones you'll have with yourself.",
              author: "David Goggins", context: "Can't Hurt Me"),
        .init(text: "When you think that you are done, you're only 40% done.",
              author: "David Goggins", context: "La règle des 40%"),
        .init(text: "Don't stop when you're tired. Stop when you're done.",
              author: "David Goggins", context: "Attribué"),
        // Jocko Willink
        .init(text: "Discipline equals freedom.",
              author: "Jocko Willink", context: "Discipline Equals Freedom, 2017"),
        .init(text: "Don't count on motivation. Count on discipline.",
              author: "Jocko Willink", context: "Discipline Equals Freedom"),
        .init(text: "It's not what you preach, it's what you tolerate.",
              author: "Jocko Willink", context: "Extreme Ownership, 2015"),
        .init(text: "Extreme ownership: leaders must own everything in their world.",
              author: "Jocko Willink", context: "Extreme Ownership"),
        // Naval Ravikant
        .init(text: "Play long-term games with long-term people.",
              author: "Naval Ravikant", context: "How to Get Rich, 2019"),
        .init(text: "Seek wealth, not money or status. Wealth is having assets that earn while you sleep.",
              author: "Naval Ravikant", context: "How to Get Rich"),
        .init(text: "The more you desire specific things, the more you suffer when you don't get them.",
              author: "Naval Ravikant", context: "Almanack of Naval Ravikant"),
        // Steve Jobs
        .init(text: "The only way to do great work is to love what you do.",
              author: "Steve Jobs", context: "Stanford, 2005"),
        .init(text: "Stay hungry. Stay foolish.",
              author: "Steve Jobs", context: "Stanford, 2005"),
        .init(text: "Your time is limited, so don't waste it living someone else's life.",
              author: "Steve Jobs", context: "Stanford, 2005"),
        .init(text: "Innovation is saying no to 1,000 things.",
              author: "Steve Jobs", context: "WWDC, 1997"),
        // Bruce Lee
        .init(text: "To hell with circumstances; I create opportunities.",
              author: "Bruce Lee", context: "Tao of Jeet Kune Do, 1975"),
        .init(text: "Absorb what is useful, discard what is not, add what is uniquely your own.",
              author: "Bruce Lee", context: "Tao of Jeet Kune Do"),
        .init(text: "Do not pray for an easy life, pray for the strength to endure a difficult one.",
              author: "Bruce Lee", context: "Tao of Jeet Kune Do"),
        .init(text: "A goal is not always meant to be reached; it often serves simply as something to aim at.",
              author: "Bruce Lee", context: "Tao of Jeet Kune Do"),
        // Athlètes & militaires
        .init(text: "We don't rise to the level of our expectations; we fall to the level of our training.",
              author: "Archilochus", context: "Poème grec, ~650 BC"),
        .init(text: "It's not the mountain we conquer, but ourselves.",
              author: "Sir Edmund Hillary", context: "1953"),
        .init(text: "Success is not final, failure is not fatal: it is the courage to continue that counts.",
              author: "Winston Churchill", context: "Attribué"),
        .init(text: "If you're going through hell, keep going.",
              author: "Winston Churchill", context: "Attribué"),
        .init(text: "You miss 100% of the shots you don't take.",
              author: "Wayne Gretzky", context: "Interview"),
        .init(text: "Strength does not come from physical capacity. It comes from an indomitable will.",
              author: "Mahatma Gandhi", context: "Young India, 1919"),
        .init(text: "Whether you think you can, or you think you can't — you're right.",
              author: "Henry Ford", context: "Attribué"),
        .init(text: "The man who moves a mountain begins by carrying away small stones.",
              author: "Confucius", context: "Analectes"),
        .init(text: "Our greatest glory is not in never falling, but in rising every time we fall.",
              author: "Confucius", context: "Analectes"),
        .init(text: "Great things are not done by impulse, but by a series of small things brought together.",
              author: "Vincent van Gogh", context: "Lettre à Théo, 1882"),
        .init(text: "Man cannot discover new oceans unless he has the courage to lose sight of the shore.",
              author: "André Gide", context: "Les Nourritures terrestres, 1897"),
        .init(text: "It always seems impossible until it's done.",
              author: "Nelson Mandela", context: "Attribué"),
        .init(text: "Do not go where the path may lead; go instead where there is no path and leave a trail.",
              author: "Ralph Waldo Emerson", context: "Essays, 1841"),
        .init(text: "The secret of getting ahead is getting started.",
              author: "Mark Twain", context: "Attribué"),
        .init(text: "Hard work beats talent when talent fails to work hard.",
              author: "Kevin Durant", context: "Attribué"),
        .init(text: "Pain is temporary. Quitting lasts forever.",
              author: "Lance Armstrong", context: "It's Not About the Bike, 2000"),
        .init(text: "Champions keep playing until they get it right.",
              author: "Billie Jean King", context: "Attribué"),
        .init(text: "You are never really playing an opponent. You are playing yourself, your own highest standards.",
              author: "Arthur Ashe", context: "Attribué"),
        .init(text: "The more I practice, the luckier I get.",
              author: "Gary Player", context: "Attribué"),
        .init(text: "You can't put a limit on anything. The more you dream, the farther you get.",
              author: "Michael Phelps", context: "No Limits, 2008"),
        .init(text: "Gold medals aren't really made of gold. They're made of sweat, determination, and a hard-to-find alloy called guts.",
              author: "Dan Gable", context: "JO 1972"),
    ]
}
