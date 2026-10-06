require "digest"
def upload_screenshot(set_id, path)
  data = File.binread(path)
  shot = ASC.post("/v1/appScreenshots", { data: { type: "appScreenshots",
    attributes: { fileName: File.basename(path), fileSize: data.bytesize },
    relationships: { appScreenshotSet: { data: { type: "appScreenshotSets", id: set_id } } } } })["data"]
  shot["attributes"]["uploadOperations"].each do |op|
    uri = URI(op["url"])
    req = Net::HTTP.const_get(op["method"].capitalize).new(uri)
    op["requestHeaders"].each { |h| req[h["name"]] = h["value"] }
    req.body = data.byteslice(op["offset"], op["length"])
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(req) }
    raise "yükleme parçası #{res.code}" unless res.code.start_with?("2")
  end
  ASC.patch("/v1/appScreenshots/#{shot["id"]}", { data: { type: "appScreenshots", id: shot["id"],
    attributes: { uploaded: true, sourceFileChecksum: Digest::MD5.hexdigest(data) } } })
  shot["id"]
end
