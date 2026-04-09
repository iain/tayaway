# frozen_string_literal: true

# Route files use `# typed: false` because Roda's DSL (hash_path, r.get,
# r.post, etc.) cannot be statically typed by Sorbet. This is an intentional
# exception to the project-wide `# typed: true` convention. See CLAUDE.md.

class App
  hash_branch("api", "task-lists") do |r|
    require_auth

    # GET /api/task-lists - List all task lists for a workspace
    r.is do
      r.get do
        workspace_id = r.params["workspace_id"]

        unless workspace_id && member_of_workspace?(workspace_id)
          response.status = 403
          next { error: "Access denied" }
        end

        task_lists = TaskList.for_workspace(workspace_id)
        pool = PoolSerializer.new(membership: current_membership)
        pool.add_all(task_lists, type: :task_list)

        response.status = 200
        { objects: pool.to_a }
      end

      # POST /api/task-lists - Create a new task list
      r.post do
        workspace_id = r.params["workspace_id"]

        unless workspace_id && member_of_workspace?(workspace_id)
          response.status = 403
          next { error: "Access denied" }
        end

        result = TaskLists::Create.call(
          workspace_id: workspace_id,
          membership: current_membership,
          name: r.params["name"]&.strip,
          id: r.params["id"]
        )
        handle_result(result, success_status: 201)
      end
    end

    # /api/task-lists/:id routes
    r.on String do |id|
      find_result = TaskList.find_result(id)
      unless find_result.success?
        error = find_result.failure
        response.status = error.http_status
        next error.to_api_hash
      end
      task_list = find_result.value!

      response.status = 403
      next { error: "Access denied" } unless member_of_workspace?(task_list.workspace_id)

      # PUT /api/task-lists/:id - Update a task list (rename and/or reposition)
      r.is do
        r.put do
          position_param = r.params["position"]
          position = position_param ? position_param.to_f : nil
          result = TaskLists::Update.call(
            task_list_id: task_list.id,
            name: r.params["name"]&.strip,
            position: position,
            membership: current_membership
          )
          handle_result(result)
        end

        # DELETE /api/task-lists/:id - Delete a task list
        r.delete do
          result = TaskLists::Delete.call(task_list_id: task_list.id, membership: current_membership)
          handle_result(result)
        end
      end

      # POST /api/task-lists/:id/items - Add an item
      r.on "items" do
        r.is do
          r.post do
            result = TaskLists::AddItem.call(
              task_list_id: task_list.id,
              membership: current_membership,
              content: r.params["content"]&.strip,
              id: r.params["id"]
            )
            handle_result(result, success_status: 201)
          end
        end

        # /api/task-lists/:id/items/:item_id routes
        r.on String do |item_id|
          # PUT /api/task-lists/:id/items/:item_id - Update an item (content, completion, position, and/or list)
          r.put do
            completed_param = r.params["completed"]
            completed = completed_param == true || completed_param == "true" ? true : (completed_param == false || completed_param == "false" ? false : nil)

            position_param = r.params["position"]
            position = position_param ? position_param.to_f : nil

            result = TaskLists::UpdateItem.call(
              task_list_id: task_list.id,
              task_item_id: item_id,
              membership: current_membership,
              content: r.params["content"]&.strip,
              completed: completed,
              position: position,
              new_task_list_id: r.params["task_list_id"]
            )
            handle_result(result)
          end

          # DELETE /api/task-lists/:id/items/:item_id - Delete an item
          r.delete do
            result = TaskLists::DeleteItem.call(
              task_list_id: task_list.id,
              task_item_id: item_id,
              membership: current_membership
            )
            handle_result(result)
          end
        end
      end

      # POST /api/task-lists/:id/clear-completed - Delete all completed items
      r.on "clear-completed" do
        r.post do
          result = TaskLists::ClearCompleted.call(task_list_id: task_list.id, membership: current_membership)
          handle_result(result)
        end
      end
    end
  end
end
