
/**
 * Please read the Capacitor iOS Plugin Development Guide
 * here: https://capacitor.ionicframework.com/docs/plugins/ios
 */
import Foundation
import Capacitor
import GoogleSignIn

@objc(GoogleAuth)
public class GoogleAuth: CAPPlugin {
    var signInCall: CAPPluginCall!
    var forceAuthCode: Bool = false
    var additionalScopes: [String]!

    public override func load() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenUrl(_:)),
            name: Notification.Name(Notification.Name.capacitorOpenURL.rawValue),
            object: nil
        )
    }

    @objc
    func initialize(_ call: CAPPluginCall) {
        guard let clientId = call.getString("clientId") ?? getClientIdValue() else {
            NSLog("No client ID found in config")
            call.resolve()
            return
        }

        let customScopes = call.getArray("scopes", String.self) ?? (
            getConfigValue("scopes") as? [String] ?? []
        )

        forceAuthCode = call.getBool("grantOfflineAccess") ?? (
            getConfigValue("forceCodeForRefreshToken") as? Bool ?? false
        )

        loadSignInClient(customClientId: clientId, customScopes: customScopes)
        call.resolve()
    }

    func loadSignInClient(customClientId: String, customScopes: [String]) {
        let serverClientId = getServerClientIdValue()
        let config = GIDConfiguration(clientID: customClientId, serverClientID: serverClientId)
        GIDSignIn.sharedInstance.configuration = config

        let defaultGrantedScopes = ["email", "profile", "openid"]
        additionalScopes = customScopes.filter {
            return !defaultGrantedScopes.contains($0)
        }
    }

    @objc
    func signIn(_ call: CAPPluginCall) {
        signInCall = call

        DispatchQueue.main.async {
            if GIDSignIn.sharedInstance.hasPreviousSignIn() && !self.forceAuthCode {
                GIDSignIn.sharedInstance.restorePreviousSignIn { user, error in
                    if let error = error {
                        self.signInCall?.reject(error.localizedDescription)
                        return
                    }
                    guard let user = user else {
                        self.signInCall?.reject("No user returned")
                        return
                    }
                    self.resolveSignInCallWith(user: user)
                }
            } else {
                guard let presentingVc = self.bridge?.viewController else {
                    call.reject("Unable to access presenting view controller")
                    return
                }

              GIDSignIn.sharedInstance.signIn(
                  withPresenting: presentingVc,
                  completion: { result, error in
                      if let error = error {
                          self.signInCall?.reject(error.localizedDescription, "\(error._code)")
                          return
                      }
                      guard let result = result else {
                          self.signInCall?.reject("No sign-in result returned")
                          return
                      }
                      self.resolveSignInCallWith(user: result.user)
                  }
              )


            }
        }
    }

    @objc
    func refresh(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            guard let user = GIDSignIn.sharedInstance.currentUser else {
                call.reject("User not logged in.")
                return
            }

            user.refreshTokensIfNeeded { _, error in
                if let error = error {
                    call.reject(error.localizedDescription)
                    return
                }

                let accessToken = user.accessToken.tokenString
                let idToken = user.idToken?.tokenString ?? ""

                let authenticationData: [String: Any] = [
                    "accessToken": accessToken,
                    "idToken": idToken,
                    "refreshToken": NSNull()
                ]
                call.resolve(authenticationData)
            }
        }
    }

    @objc
    func signOut(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            GIDSignIn.sharedInstance.signOut()
        }
        call.resolve()
    }

    @objc
    func handleOpenUrl(_ notification: Notification) {
        guard let object = notification.object as? [String: Any],
              let url = object["url"] as? URL else {
            print("No URL object in handleOpenUrl")
            return
        }
        _ = GIDSignIn.sharedInstance.handle(url)
    }

    func getClientIdValue() -> String? {
        if let clientId = getConfig().getString("iosClientId") {
            return clientId
        } else if let clientId = getConfig().getString("clientId") {
            return clientId
        } else if let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
                  let dict = NSDictionary(contentsOfFile: path) as? [String: AnyObject],
                  let clientId = dict["CLIENT_ID"] as? String {
            return clientId
        }
        return nil
    }

    func getServerClientIdValue() -> String? {
        if let serverClientId = getConfig().getString("serverClientId") {
            return serverClientId
        }
        return nil
    }

    func resolveSignInCallWith(user: GIDGoogleUser) {
        var userData: [String: Any] = [
            "authentication": [
                "accessToken": user.accessToken.tokenString,
                "idToken": user.idToken?.tokenString ?? NSNull(),
                "refreshToken": NSNull()
            ],
            "email": user.profile?.email ?? NSNull(),
            "familyName": user.profile?.familyName ?? NSNull(),
            "givenName": user.profile?.givenName ?? NSNull(),
            "id": user.userID ?? NSNull(),
            "name": user.profile?.name ?? NSNull()
        ]

        if let imageUrl = user.profile?.imageURL(withDimension: 100)?.absoluteString {
            userData["imageUrl"] = imageUrl
        }

        signInCall?.resolve(userData)
    }
}
