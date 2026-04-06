# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Task lists endpoints" do
  let(:user) { TestFactories.user }
  let(:session) { TestFactories.session(user: user) }
  let(:auth_cookie) { { "HTTP_COOKIE" => "session_token=#{session[:token]}" } }
  let(:csrf_header) { { "HTTP_X_CSRF_PROTECTION" => "1" } }
  let(:auth_headers) { auth_cookie.merge(csrf_header) }
  let(:workspace) { TestFactories.workspace }

  before { TestFactories.workspace_membership(workspace: workspace, user: user) }

  describe "GET /api/task-lists" do
    it "returns 401 without auth" do
      get "/api/task-lists"

      expect(last_response.status).to eq(401)
    end

    it "returns 403 when not a member of workspace" do
      other_workspace = TestFactories.workspace

      get "/api/task-lists?workspace_id=#{other_workspace[:id]}", {}, auth_cookie

      expect(last_response.status).to eq(403)
    end

    it "returns task lists for the workspace" do
      TestFactories.task_list(workspace: workspace, user: user, name: "Shopping")

      get "/api/task-lists?workspace_id=#{workspace[:id]}", {}, auth_cookie

      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      list = body["objects"].find { |o| o["objectType"] == "taskList" }
      expect(list["name"]).to eq("Shopping")
    end
  end

  describe "POST /api/task-lists" do
    it "returns 401 without auth" do
      post "/api/task-lists"

      expect(last_response.status).to eq(401)
    end

    it "returns 403 when not a member of workspace" do
      other_workspace = TestFactories.workspace

      post "/api/task-lists", { workspace_id: other_workspace[:id], name: "My List" }.to_json,
           auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(403)
    end

    it "creates a task list" do
      post "/api/task-lists",
           { workspace_id: workspace[:id], name: "Groceries" }.to_json,
           auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(201)
      body = JSON.parse(last_response.body)
      list = body["objects"].find { |o| o["objectType"] == "taskList" }
      expect(list["name"]).to eq("Groceries")
    end

    it "returns 422 when name is missing" do
      post "/api/task-lists",
           { workspace_id: workspace[:id] }.to_json,
           auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(400)
    end
  end

  describe "PUT /api/task-lists/:id" do
    it "returns 404 when task list not found" do
      put "/api/task-lists/#{SecureRandom.uuid}",
          { name: "New Name" }.to_json,
          auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(404)
    end

    it "renames a task list" do
      list = TestFactories.task_list(workspace: workspace, user: user, name: "Old")

      put "/api/task-lists/#{list[:id]}",
          { name: "New" }.to_json,
          auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      updated = body["objects"].find { |o| o["objectType"] == "taskList" }
      expect(updated["name"]).to eq("New")
    end
  end

  describe "DELETE /api/task-lists/:id" do
    it "deletes a task list" do
      list = TestFactories.task_list(workspace: workspace, user: user)

      delete "/api/task-lists/#{list[:id]}", {}, auth_headers

      expect(last_response.status).to eq(200)
      expect(DB[:task_lists].where(id: list[:id]).count).to eq(0)
    end
  end

  describe "POST /api/task-lists/:id/items" do
    it "adds an item to a task list" do
      list = TestFactories.task_list(workspace: workspace, user: user)

      post "/api/task-lists/#{list[:id]}/items",
           { content: "Buy milk" }.to_json,
           auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(201)
      body = JSON.parse(last_response.body)
      item = body["objects"].find { |o| o["objectType"] == "taskItem" }
      expect(item["content"]).to eq("Buy milk")
    end

    it "returns 422 when content is missing" do
      list = TestFactories.task_list(workspace: workspace, user: user)

      post "/api/task-lists/#{list[:id]}/items",
           {}.to_json,
           auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(400)
    end
  end

  describe "PUT /api/task-lists/:id/items/:item_id" do
    it "marks an item as completed" do
      list = TestFactories.task_list(workspace: workspace, user: user)
      item = TestFactories.task_item(task_list: list, user: user)

      put "/api/task-lists/#{list[:id]}/items/#{item[:id]}",
          { completed: true }.to_json,
          auth_headers.merge("CONTENT_TYPE" => "application/json")

      expect(last_response.status).to eq(200)
      body = JSON.parse(last_response.body)
      updated = body["objects"].find { |o| o["objectType"] == "taskItem" && o["id"] == item[:id] }
      expect(updated["completedAt"]).not_to be_nil
    end
  end

  describe "DELETE /api/task-lists/:id/items/:item_id" do
    it "deletes an item" do
      list = TestFactories.task_list(workspace: workspace, user: user)
      item = TestFactories.task_item(task_list: list, user: user)

      delete "/api/task-lists/#{list[:id]}/items/#{item[:id]}", {}, auth_headers

      expect(last_response.status).to eq(200)
      expect(DB[:task_items].where(id: item[:id]).count).to eq(0)
    end
  end

  describe "POST /api/task-lists/:id/clear-completed" do
    it "clears completed items" do
      list = TestFactories.task_list(workspace: workspace, user: user)
      item = TestFactories.task_item(task_list: list, user: user, completed_at: Time.now)
      TestFactories.task_item(task_list: list, user: user) # not completed

      post "/api/task-lists/#{list[:id]}/clear-completed", {}, auth_headers

      expect(last_response.status).to eq(200)
      expect(DB[:task_items].where(id: item[:id]).count).to eq(0)
      expect(DB[:task_items].where(task_list_id: list[:id]).count).to eq(1)
    end
  end
end
