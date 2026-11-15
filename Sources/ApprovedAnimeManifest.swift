import Foundation

/// SHA-256 hashes from the exact owner-approved, unmodified Anime-Squad archive.
/// Pinned independently of mutable device journal contents.
enum ApprovedAnimeManifest {
    static let files: [String: String] = [
        "com.apple.posterkit.provider.descriptor.identifier": "7078c7f8564ee0300ee371c8511553483f3465110b7b962bd63822b541aa8892",
        "com.apple.posterkit.provider.identifierURL.suggestionMetadata.plist": "b359d11cdb7eaabd1878ce935edecfb7e98ac38c1c78e8394518b57f5e3f2c65",
        "com.apple.posterkit.role.identifier": "ce6a53a6eef62fe767aaa54a33ca9dcc29cce6f84f471d71f1d0167abe087ce7",
        "providerInfo.plist": "697dc3b7a7d93849757f664fea1b830d3bdc661a9fcdad43b71870fd602083f1",
        "versions/1/RuntimeSnapshotMetadata-home.plist": "78c6651211d4abdde0e987f3420a3102e113361201c78331e9aa50d3b6db1d99",
        "versions/1/RuntimeSnapshotMetadata-lock.plist": "1e971720e91261d9369a4029b70081ccf33ce6ce9b1945c3319dbeeb465dda48",
        "versions/1/com.apple.posterkit.provider.instance.complicationLayout.plist": "6f70cdde0e28fec881f8e3fb1712d5b72d892bd4f885a53bc6d93174da03d745",
        "versions/1/com.apple.posterkit.provider.instance.titleStyleConfiguration.plist": "2bc4be91f199c2c5db7acfb7ae8f9581eb292498ecd0cddbe8d1ac3edf43e92a",
        "versions/1/contents/.com.apple.posterkit.provider.contents.configurableOptions.plist": "2b5decfc32306577b28df137eed469628f02307c3caed18ee3bc4a141e1caf55",
        "versions/1/contents/7400.WWDC_2022-390w-844h@3x~iphone.wallpaper/7400.WWDC_2022_Background-390w-844h@3x~iphone.ca/assetManifest.caml": "6a2ce34b3c37b6c49f6081f98fd274838c50bf88ac4b5a6afadacbd61212f11f",
        "versions/1/contents/7400.WWDC_2022-390w-844h@3x~iphone.wallpaper/7400.WWDC_2022_Background-390w-844h@3x~iphone.ca/assets/back.png": "789da70a0436e23a8dbe938afe7d949d9913048b79c5bcdc7cf01dbe2768c847",
        "versions/1/contents/7400.WWDC_2022-390w-844h@3x~iphone.wallpaper/7400.WWDC_2022_Background-390w-844h@3x~iphone.ca/assets/gojo.png": "19952ff5568d115c643a5f61b07c4d93c96580a13f310c5c4859de98ffab15bb",
        "versions/1/contents/7400.WWDC_2022-390w-844h@3x~iphone.wallpaper/7400.WWDC_2022_Background-390w-844h@3x~iphone.ca/index.xml": "6a0870d93f39195c9e5e5652ad1e8447e90efbc0615b2d03f3ee4bd3ee40c60d",
        "versions/1/contents/7400.WWDC_2022-390w-844h@3x~iphone.wallpaper/7400.WWDC_2022_Background-390w-844h@3x~iphone.ca/main.caml": "7e8fb9e413cf81db584eb1fad2f963dd7e6030c8fc72d4bd4375ba9079e774ee",
        "versions/1/contents/7400.WWDC_2022-390w-844h@3x~iphone.wallpaper/7400.WWDC_2022_Floating-390w-844h@3x~iphone.ca/assetManifest.caml": "6a2ce34b3c37b6c49f6081f98fd274838c50bf88ac4b5a6afadacbd61212f11f",
        "versions/1/contents/7400.WWDC_2022-390w-844h@3x~iphone.wallpaper/7400.WWDC_2022_Floating-390w-844h@3x~iphone.ca/assets/boruto.png": "31bb6435d02f4559d9425e39608d24b1de28f04e186f1f27b140b17b8b8b03df",
        "versions/1/contents/7400.WWDC_2022-390w-844h@3x~iphone.wallpaper/7400.WWDC_2022_Floating-390w-844h@3x~iphone.ca/index.xml": "6a0870d93f39195c9e5e5652ad1e8447e90efbc0615b2d03f3ee4bd3ee40c60d",
        "versions/1/contents/7400.WWDC_2022-390w-844h@3x~iphone.wallpaper/7400.WWDC_2022_Floating-390w-844h@3x~iphone.ca/main.caml": "61ae56f631d4e272191bcb725607cd28bf73d83d35e5f03440ab586d03f733e3",
        "versions/1/contents/7400.WWDC_2022-390w-844h@3x~iphone.wallpaper/7400.WWDC_2022_Foreground-390w-844h@3x~iphone.ca/assetManifest.caml": "6a2ce34b3c37b6c49f6081f98fd274838c50bf88ac4b5a6afadacbd61212f11f",
        "versions/1/contents/7400.WWDC_2022-390w-844h@3x~iphone.wallpaper/7400.WWDC_2022_Foreground-390w-844h@3x~iphone.ca/assets/naruto.png": "a9d6615f7a5418e8a515af419291e60d5cd21d9ec64c2e7a61dcde945e64c26a",
        "versions/1/contents/7400.WWDC_2022-390w-844h@3x~iphone.wallpaper/7400.WWDC_2022_Foreground-390w-844h@3x~iphone.ca/index.xml": "6a0870d93f39195c9e5e5652ad1e8447e90efbc0615b2d03f3ee4bd3ee40c60d",
        "versions/1/contents/7400.WWDC_2022-390w-844h@3x~iphone.wallpaper/7400.WWDC_2022_Foreground-390w-844h@3x~iphone.ca/main.caml": "741018e92c81238f428298d076944d723c81220541e0d6a761c3d433711a74df",
        "versions/1/contents/7400.WWDC_2022-390w-844h@3x~iphone.wallpaper/Wallpaper.plist": "5c862ce6e99290dd05ff509272e4e7ceb140cf10c545e5d988157e764b7297ba",
        "versions/1/contents/com.apple.posterkit.provider.contents.otherMetadata.plist": "415d32c8a0461649b1dce0e6463959d65997a261c1e95f1995b075863201f11d",
        "versions/1/contents/com.apple.posterkit.provider.contents.userInfo": "bc6bcc3dff2639aad9cf9e6e4cb46b7164f877dc93f28f5a74bf3722a44e93c1",
        "versions/1/supplements/0/com.apple.posterkit.provider.supplementURL.homescreenConfiguration.plist": "92ffd3ddccc732421f5219e006cae6d08aefb583076124ba31821d365e3a87ad"
    ]
}
