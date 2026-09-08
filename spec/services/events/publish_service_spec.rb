require "rails_helper"

RSpec.describe Events::PublishService do
  let!(:category) { EventCategory.create!(name: "Parties") }
  let(:event) do
    Event.create!(name: "Pizza party", event_category: category,
                  starts_at: Time.zone.parse("2026-09-18 18:30"), ends_at: Time.zone.parse("2026-09-18 22:00"))
  end

  it "publie avec le slug proposé, une seule fois" do
    published_event = described_class.new(event: event).publish!
    expect(published_event.published_at).to be_present
    expect(published_event.slug).to eq("pizza-party-septembre-2026")

    first_publication = published_event.published_at
    described_class.new(event: published_event).publish!
    expect(published_event.reload.published_at).to eq(first_publication)
  end

  it "accepte un slug choisi à la première publication" do
    described_class.new(event: event).publish!(slug: "Pizza Party Rentrée")
    expect(event.reload.slug).to eq("pizza-party-rentree")
  end

  it "refuse de changer le slug d'une fiche déjà publiée" do
    described_class.new(event: event).publish!
    expect { described_class.new(event: event).publish!(slug: "autre") }.to raise_error(ActiveRecord::RecordInvalid)
    expect(event.reload.slug).to eq("pizza-party-septembre-2026")
  end

  it "dépublie sans toucher au slug" do
    described_class.new(event: event).publish!
    described_class.new(event: event).unpublish!
    expect(event.reload.published_at).to be_nil
    expect(event.slug).to eq("pizza-party-septembre-2026")
  end
end
