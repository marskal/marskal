require "test_helper"

class ProjectNavTreeTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @tree = ProjectNavTree.new(@user)
  end

  test "roots are active top-level folders ordered by name" do
    names = @tree.root_folders.map(&:name)

    assert_includes names, "Work"
    assert_not_includes names, "Client A"
    assert_not_includes names, "Old stuff"
    assert_not_includes names, "Their Work"
  end

  test "nests child folders and open projects" do
    work = project_folders(:work)

    assert_equal [ "Client A" ], @tree.child_folders(work).map(&:name)
    assert_equal [ "Launch website" ], @tree.projects_in(project_folders(:client_a)).map(&:title)
    assert @tree.expandable?(work)
  end

  test "unfiled open projects sit at the root of the tree" do
    titles = @tree.unfiled_projects.map(&:title)

    assert_includes titles, "Plan vacation"
    assert_not_includes titles, "Launch website"
    assert_not_includes titles, "Finish onboarding"
    assert_not_includes titles, "Secret project"
  end

  test "does not hoist children of dropped folders" do
    dropped = @user.project_folders.create!(name: "Parked", state: :dropped)
    child = @user.project_folders.create!(name: "Still Active", parent: dropped)
    @user.projects.create!(title: "Hidden work", project_folder: child)

    tree = ProjectNavTree.new(@user)
    names = collect_folder_names(tree)

    assert_not_includes names, "Parked"
    assert_not_includes names, "Still Active"
    assert_not_includes tree.unfiled_projects.map(&:title), "Hidden work"
  end

  test "empty when the user has no visible folders or projects" do
    user = User.create!(email_address: "empty@marskal.example", password: "password12")

    assert ProjectNavTree.new(user).empty?
    assert_not @tree.empty?
  end

  test "nil user is an empty tree" do
    tree = ProjectNavTree.new(nil)

    assert tree.empty?
    assert_equal [], tree.root_folders
    assert_equal [], tree.unfiled_projects
  end

  private
    def collect_folder_names(tree, folders = tree.root_folders)
      folders.flat_map { |folder| [ folder.name ] + collect_folder_names(tree, tree.child_folders(folder)) }
    end
end
