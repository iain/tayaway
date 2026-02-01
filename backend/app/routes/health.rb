class App
  hash_path "/health" do |r|
    r.get do
      { status: "healthy" }
    end
  end
end
