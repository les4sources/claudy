require 'rails_helper'

# == Schema Information
#
# Table name: gathering_actions
#
#  id           :bigint           not null, primary key
#  completed    :boolean          default(FALSE), not null
#  completed_at :datetime
#  deleted_at   :datetime
#  label        :string           not null
#  position     :integer          default(0), not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  gathering_id :bigint           not null
#
# Indexes
#
#  index_gathering_actions_on_deleted_at                 (deleted_at)
#  index_gathering_actions_on_gathering_id               (gathering_id)
#  index_gathering_actions_on_gathering_id_and_position  (gathering_id,position)
#
# Foreign Keys
#
#  fk_rails_...  (gathering_id => gatherings.id)
#
RSpec.describe GatheringAction, type: :model do
  let(:category) { GatheringCategory.create!(name: "Réunion", color: "emerald") }
  let(:gathering) do
    Gathering.create!(name: "G", gathering_category: category,
                      starts_at: Time.current, ends_at: Time.current + 1.hour)
  end
  let(:alice) { Human.create!(name: "Alice #{SecureRandom.hex(3)}") }
  let(:bob)   { Human.create!(name: "Bob #{SecureRandom.hex(3)}") }

  def build_action(attrs = {})
    gathering.gathering_actions.create!({ label: "Acheter du bois" }.merge(attrs))
  end

  it "requires a label" do
    action = gathering.gathering_actions.build(label: nil)
    expect(action).not_to be_valid
  end

  it "can be assigned to several humans" do
    action = build_action(assignees: [alice, bob])
    expect(action.assignees).to contain_exactly(alice, bob)
  end

  it "surfaces on each assigned human" do
    action = build_action(assignees: [alice])
    expect(alice.gathering_actions).to include(action)
  end

  describe "#toggle_completed!" do
    it "marks the shared action done and stamps completed_at" do
      action = build_action
      action.toggle_completed!
      expect(action.completed).to be(true)
      expect(action.completed_at).to be_present
    end

    it "reverts to not done and clears completed_at" do
      action = build_action(completed: true, completed_at: Time.current)
      action.toggle_completed!
      expect(action.completed).to be(false)
      expect(action.completed_at).to be_nil
    end
  end

  describe "ordered scope" do
    it "puts pending actions before completed ones" do
      done = build_action(completed: true)
      todo = build_action
      expect(gathering.gathering_actions.ordered.to_a).to eq([todo, done])
    end
  end
end
