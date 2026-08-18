require "test_helper"

class TaskTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  test "defaults to inbox and to_do" do
    task = @user.tasks.create!(title: "New capture")

    assert task.inbox?
    assert task.to_do?
  end

  test "database assigns a uuidv7 primary key" do
    task = @user.tasks.create!(title: "New capture")

    assert_match(
      /\A[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i,
      task.id
    )
  end

  test "accepts a client-supplied uuid" do
    id = SecureRandom.uuid_v7
    task = @user.tasks.create!(id: id, title: "Offline capture")

    assert_equal id, task.reload.id
  end

  test "requires title" do
    task = @user.tasks.new(title: "")

    assert_not task.valid?
    assert_includes task.errors[:title], "can't be blank"
  end

  test "rejects invalid state" do
    task = @user.tasks.new(title: "X", state: "bogus")

    assert_not task.valid?
    assert task.errors[:state].any?
  end

  test "open_stream is to_do and not inbox" do
    open_ids = Task.open_stream.pluck(:id)

    assert_includes open_ids, tasks(:open_one).id
    assert_not_includes open_ids, tasks(:inbox_one).id
    assert_not_includes open_ids, tasks(:done_one).id
  end

  test "move_to_open leaves inbox" do
    task = tasks(:inbox_one)

    task.move_to_open!

    assert_not task.reload.inbox?
    assert task.to_do?
  end

  test "complete and drop set terminal states" do
    task = tasks(:open_one)

    task.complete!
    assert task.reload.done?

    task.reopen!
    assert task.reload.to_do?

    task.drop!
    assert task.reload.dropped?
  end

  test "can belong to own project" do
    task = tasks(:open_one)
    project = projects(:website)

    task.update!(project: project)

    assert_equal project, task.reload.project
  end

  test "rejects project owned by another user" do
    task = tasks(:open_one)
    task.project = projects(:other_user_project)

    assert_not task.valid?
    assert task.errors[:project].any?
  end

  test "project task appears on open stream" do
    assert_includes Task.open_stream.pluck(:id), tasks(:project_task).id
  end
end

