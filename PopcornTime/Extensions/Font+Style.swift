

import Foundation


enum FontStyle: String, Codable {
    case bold = "Bold"
    case italic = "Italic"
    case boldItalic = "Bold-Italic"
    case normal = "Normal"
    
    static let arrayValue = [bold, italic, boldItalic, normal]
    
    var localizedString: String {
        return self.rawValue.localized
    }
}
