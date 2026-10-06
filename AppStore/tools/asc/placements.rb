require_relative "asc"
LIB = JSON.parse(File.read(File.expand_path("~/Projects/Ciki/AppStore/asset-library.json")))
images = {}
url = "/v1/appAssetLibraries/6819577900/images?limit=200"
while url
  r = ASC.get(url); r["data"].each { |i| images[i["attributes"]["referenceName"]] = i["id"] }; url = r.dig("links", "next")
end

def place(type, image, rel, loc_type, loc_id, label)
  existing = ASC.get("/v1/#{loc_type}/#{loc_id}/placements?limit=200")["data"].map { |p| p["attributes"]["placementType"] }
  return puts("• #{label} #{type} zaten var") if existing.include?(type)
  ASC.post("/v1/appAssetLibraryPlacements", { data: { type: "appAssetLibraryPlacements", attributes: { placementType: type },
    relationships: { image: { data: { type: "appAssetLibraryImages", id: image } }, rel => { data: { type: loc_type, id: loc_id } } } } })
  puts "✓ #{label} #{type}"
end

# Varsayılan ürün sayfası (iOS sürümü)
ASC.get("/v1/appStoreVersions/6a372b38-8d3f-402e-b7bd-92abe61cedc6/appStoreVersionLocalizations")["data"].each do |l|
  loc = l["attributes"]["locale"]
  place("PRODUCT_PAGE_HEADER_ASSET", images.fetch("#{loc}-header-urun-3840x1646.png"), :appStoreVersionLocalization, "appStoreVersionLocalizations", l["id"], "varsayılan #{loc}")
  place("APP_STORE_SEARCH_RESULTS_ASSET", images.fetch("#{loc}-search-varsayilan-3840x2560.jpg"), :appStoreVersionLocalization, "appStoreVersionLocalizations", l["id"], "varsayılan #{loc}")
end

# Özel ürün sayfaları
pages = ASC.get("/v1/apps/6819577900/appCustomProductPages?limit=50")["data"].to_h { |p| [p["attributes"]["name"], p["id"]] }
LIB["customProductPages"].each do |cpp|
  page = pages.fetch(cpp["name"]["tr"])
  version = ASC.get("/v1/appCustomProductPages/#{page}/appCustomProductPageVersions")["data"].first["id"]
  ASC.get("/v1/appCustomProductPageVersions/#{version}/appCustomProductPageLocalizations")["data"].each do |l|
    loc = l["attributes"]["locale"]
    place("PRODUCT_PAGE_HEADER_ASSET", images.fetch("#{loc}-#{cpp["header"]}-3840x1646.png"), :appCustomProductPageLocalization, "appCustomProductPageLocalizations", l["id"], "#{cpp["id"]} #{loc}")
    place("APP_STORE_SEARCH_RESULTS_ASSET", images.fetch("#{loc}-search-#{cpp["id"]}-3840x2560.jpg"), :appCustomProductPageLocalization, "appCustomProductPageLocalizations", l["id"], "#{cpp["id"]} #{loc}")
  end
end
