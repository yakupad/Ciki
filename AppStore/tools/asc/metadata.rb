require_relative "asc"
APP = "6819577900"
INFO = "0eeb032d-43dc-455f-ab60-ecb2ee635b20"
VERSIONS = { "IOS" => "6a372b38-8d3f-402e-b7bd-92abe61cedc6", "MAC_OS" => "2d46be24-46d5-4113-88be-5815e83a8d6d" }
DIR = File.expand_path("~/Projects/Ciki/AppStore/metadata")
def text(locale, name) = File.read("#{DIR}/#{locale == "tr" ? "tr" : "en-US"}/#{name}.txt").strip

# Kategori: Finans, ikincil Verimlilik
ASC.patch("/v1/appInfos/#{INFO}", { data: { type: "appInfos", id: INFO, relationships: {
  primaryCategory: { data: { type: "appCategories", id: "FINANCE" } },
  secondaryCategory: { data: { type: "appCategories", id: "PRODUCTIVITY" } } } } })
puts "✓ kategori"

# Uygulama bilgisi (ad, alt başlık)
existing = ASC.get("/v1/appInfos/#{INFO}/appInfoLocalizations")["data"].to_h { |l| [l["attributes"]["locale"], l["id"]] }
%w[tr en-US].each do |locale|
  attrs = { name: text(locale, "name"), subtitle: text(locale, "subtitle"), privacyPolicyUrl: text(locale, "privacy_url") }
  if (id = existing[locale])
    ASC.patch("/v1/appInfoLocalizations/#{id}", { data: { type: "appInfoLocalizations", id: id, attributes: attrs } })
  else
    ASC.post("/v1/appInfoLocalizations", { data: { type: "appInfoLocalizations", attributes: attrs.merge(locale: locale),
      relationships: { appInfo: { data: { type: "appInfos", id: INFO } } } } })
  end
  puts "✓ uygulama bilgisi #{locale}"
end

# Sürüm metinleri (açıklama, anahtar kelimeler, tanıtım metni). İlk sürümde "Yenilikler" alanı kabul edilmez.
VERSIONS.each do |platform, version|
  locs = ASC.get("/v1/appStoreVersions/#{version}/appStoreVersionLocalizations")["data"].to_h { |l| [l["attributes"]["locale"], l["id"]] }
  %w[tr en-US].each do |locale|
    attrs = { description: text(locale, "description"), keywords: text(locale, "keywords"), promotionalText: text(locale, "promotional_text"),
              supportUrl: text(locale, "support_url") }
    if (id = locs[locale])
      ASC.patch("/v1/appStoreVersionLocalizations/#{id}", { data: { type: "appStoreVersionLocalizations", id: id, attributes: attrs } })
    else
      ASC.post("/v1/appStoreVersionLocalizations", { data: { type: "appStoreVersionLocalizations", attributes: attrs.merge(locale: locale),
        relationships: { appStoreVersion: { data: { type: "appStoreVersions", id: version } } } } })
    end
    puts "✓ #{platform} #{locale}"
  end
end
