import SwiftUI

@main
struct WooriHaruApp: App {
    @State private var authVM = AuthViewModel()

    var body: some Scene {
        WindowGroup {
            Group {
                if authVM.isLoading {
                    ProgressView()
                } else if authVM.isLoggedIn {
                    ContentView()
                } else {
                    LoginView()
                }
            }
            .environment(authVM)
            .task {
                await authVM.checkSession()
            }
        }
    }
}
