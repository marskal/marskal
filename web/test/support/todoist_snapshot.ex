defmodule TodoistSnapshot do
  @moduledoc false

  def json, do: Jason.encode!(small())

  def small do
    %{
      "sync_token" => "snapshot-1",
      "full_sync" => true,
      "user" => %{"email" => "ada@example.com", "inbox_project_id" => "in1"},
      "folders" => [
        %{"id" => "fold1", "name" => "Work", "is_deleted" => false, "child_order" => 1},
        %{"id" => "fold2", "name" => "Old", "is_deleted" => true}
      ],
      "projects" => [
        %{"id" => "in1", "name" => "Inbox", "inbox_project" => true},
        %{
          "id" => "p1",
          "name" => "Launch",
          "folder_id" => "fold1",
          "description" => "Site",
          "child_order" => 1
        },
        %{"id" => "p2", "name" => "Child", "parent_id" => "p1"},
        %{"id" => "p3", "name" => "Paused", "status" => "PAUSED"},
        %{"id" => "p4", "name" => "Archive", "is_archived" => true},
        %{"id" => "p5", "name" => "Gone", "is_deleted" => true}
      ],
      "sections" => [
        %{"id" => "s1", "name" => "Now", "project_id" => "p1", "is_deleted" => false}
      ],
      "labels" => [
        %{"id" => "l1", "name" => "Food", "item_order" => 1, "is_deleted" => false},
        %{"id" => "l2", "name" => "Gone", "is_deleted" => true}
      ],
      "items" => [
        %{
          "id" => "t1",
          "content" => "Buy milk",
          "project_id" => "in1",
          "labels" => ["Food", "Errand"],
          "priority" => 4,
          "due" => %{"date" => "2026-09-28", "string" => "every monday", "is_recurring" => true},
          "deadline" => %{"date" => "2026-10-01"},
          "checked" => false
        },
        %{
          "id" => "t2",
          "content" => "Write copy",
          "description" => "Home page",
          "project_id" => "p1",
          "section_id" => "s1",
          "checked" => false
        },
        %{"id" => "t3", "content" => "Ask editor", "project_id" => "p1", "parent_id" => "t2"},
        %{"id" => "t4", "content" => "Shipped", "project_id" => "p1", "checked" => true},
        %{"id" => "t5", "content" => "Deleted", "project_id" => "p1", "is_deleted" => true},
        %{"id" => "t6", "content" => "Orphan", "project_id" => "p5"}
      ]
    }
  end
end
