class App
  hash_branch "api" do |r|
    r.on "health" do
      r.get do
        { status: "healthy" }
      end
    end

    # Add API routes here
    # r.on "users" do
    #   r.get { User.all.map(&:to_hash) }
    # end
  end
end
