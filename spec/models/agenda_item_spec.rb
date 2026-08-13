require 'rails_helper'

# == Schema Information
#
# Table name: agenda_items
#
#  id           :bigint           not null, primary key
#  completed    :boolean          default(FALSE), not null
#  deleted_at   :datetime
#  list         :integer          default(0), not null
#  position     :integer          default(0), not null
#  title        :string           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  author_id    :bigint           not null
#  carrier_id   :bigint
#  gathering_id :bigint           not null
#
# Indexes
#
#  index_agenda_items_on_author_id                           (author_id)
#  index_agenda_items_on_carrier_id                          (carrier_id)
#  index_agenda_items_on_gathering_id                        (gathering_id)
#  index_agenda_items_on_gathering_id_and_list_and_position  (gathering_id,list,position)
#  index_agenda_items_on_gathering_id_and_position           (gathering_id,position)
#
# Foreign Keys
#
#  fk_rails_...  (author_id => humans.id)
#  fk_rails_...  (carrier_id => humans.id)
#  fk_rails_...  (gathering_id => gatherings.id)
#
RSpec.describe AgendaItem, type: :model do
  let(:category) { GatheringCategory.create!(name: "Réunion", color: "emerald") }
  let(:gathering) do
    Gathering.create!(name: "G", gathering_category: category,
                      starts_at: Time.current, ends_at: Time.current + 1.hour)
  end
  let(:author) { Human.create!(name: "Author #{SecureRandom.hex(3)}") }
  let(:carrier) { Human.create!(name: "Carrier #{SecureRandom.hex(3)}") }

  def build_item(attrs = {})
    gathering.agenda_items.create!({ title: "T", author: author }.merge(attrs))
  end

  describe "lists" do
    it "defaults to the atelier list" do
      expect(build_item.list).to eq("atelier")
    end

    it "exposes the four lists in display order" do
      expect(AgendaItem.lists.keys).to eq(%w[atelier informations triage decisions])
    end

    it "labels lists in French" do
      expect(AgendaItem.list_label("decisions")).to eq("Décisions")
    end
  end

  describe "position scoping per (gathering, list)" do
    it "increments position within the same list" do
      a = build_item(list: "atelier")
      b = build_item(list: "atelier")
      expect([a.position, b.position]).to eq([0, 1])
    end

    it "restarts position in a different list" do
      build_item(list: "atelier")
      c = build_item(list: "triage")
      expect(c.position).to eq(0)
    end
  end

  describe "carrier (porteur)" do
    it "is optional" do
      expect(build_item(carrier: nil)).to be_valid
    end

    it "can be assigned a Human" do
      expect(build_item(carrier: carrier).carrier).to eq(carrier)
    end
  end
end
