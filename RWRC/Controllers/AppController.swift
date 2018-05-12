
import UIKit
import Firebase

final class AppController {
  
  static let shared = AppController()
  
  private var window: UIWindow!
  private var rootViewController: UIViewController? {
    didSet {
      if let vc = rootViewController {
        window.rootViewController = vc
      }
    }
  }
  
  func show(in window: UIWindow?) {
    guard let window = window else {
      fatalError("Cannot layout app with a nil window.")
    }
    
    FirebaseApp.configure()
    
    self.window = window
    window.backgroundColor = .white
    
    if let user = Auth.auth().currentUser {
      let vc = ChannelsViewController(currentUser: user)
      rootViewController = NavigationController(vc)
    } else {
      rootViewController = LoginViewController()
    }
    
    window.makeKeyAndVisible()
  }
  
}
