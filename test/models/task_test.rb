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
end
