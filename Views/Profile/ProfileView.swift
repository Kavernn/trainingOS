import SwiftUI

struct ProfileView: View {
    @StateObject private var api = APIService.shared

    var body: some View {
        NavigationView {
            ZStack {
                Color(hex: "080810").ignoresSafeArea()
                if let profile = api.dashboard?.profile {
                    List {
                        Section {
                            VStack(spacing: 8) {
                                Image(systemName: "person.circle.fill")
                                    .font(.system(size: 72))
                                    .foregroundColor(.orange)
                                Text(profile.name ?? "Athlète")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .listRowBackground(Color(hex: "11111c"))
                        }

                        Section("Stats") {
                            if let w = profile.weight {
                                ProfileRow(label: "Poids", value: "\(w) lbs")
                            }
                            if let h = profile.height {
                                ProfileRow(label: "Taille", value: "\(Int(h)) cm")
                            }
                        }
                        .listRowBackground(Color(hex: "11111c"))
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                } else {
                    ProgressView().tint(.orange)
                }
            }
            .navigationTitle("Profil")
            .navigationBarTitleDisplayMode(.large)
        }
        .task { if api.dashboard == nil { await api.fetchDashboard() } }
    }
}

struct ProfileRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).foregroundColor(.gray)
            Spacer()
            Text(value).foregroundColor(.white).fontWeight(.semibold)
        }
    }
}
