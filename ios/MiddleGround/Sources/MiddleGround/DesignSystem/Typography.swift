import SwiftUI

enum MGFonts {
    static let heading = Font.Design.rounded
    
    static let displayXL = Font.system(size: 48, weight: .bold, design: .rounded)
    static let displayL = Font.system(size: 36, weight: .bold, design: .rounded)
    static let h1 = Font.system(size: 28, weight: .bold, design: .rounded)
    static let h2 = Font.system(size: 22, weight: .semibold, design: .rounded)
    static let h3 = Font.system(size: 18, weight: .semibold, design: .rounded)
    
    static let body = Font.system(size: 16, weight: .regular, design: .default)
    static let bodySmall = Font.system(size: 14, weight: .regular, design: .default)
    static let caption = Font.system(size: 12, weight: .semibold, design: .default)
}

extension View {
    func mgDisplayXL() -> some View {
        self.font(MGFonts.displayXL)
            .foregroundStyle(MGColors.slate)
    }
    
    func mgDisplayL() -> some View {
        self.font(MGFonts.displayL)
            .foregroundStyle(MGColors.slate)
    }
    
    func mgH1() -> some View {
        self.font(MGFonts.h1)
            .foregroundStyle(MGColors.slate)
    }
    
    func mgH2() -> some View {
        self.font(MGFonts.h2)
            .foregroundStyle(MGColors.slate)
    }
    
    func mgH3() -> some View {
        self.font(MGFonts.h3)
            .foregroundStyle(MGColors.slate)
    }
    
    func mgBody() -> some View {
        self.font(MGFonts.body)
            .foregroundStyle(MGColors.slate)
    }
    
    func mgBodySmall() -> some View {
        self.font(MGFonts.bodySmall)
            .foregroundStyle(MGColors.warm600)
    }
    
    func mgCaption() -> some View {
        self.font(MGFonts.caption)
            .foregroundStyle(MGColors.warm600)
    }
}
