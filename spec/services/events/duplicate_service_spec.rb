require "rails_helper"

RSpec.describe Events::DuplicateService do
  let!(:category) { EventCategory.create!(name: "Parties") }
  let(:source) do
    Event.create!(
      name: "Pizza party", event_category: category,
      starts_at: Time.zone.parse("2026-09-18 18:30"), ends_at: Time.zone.parse("2026-09-18 22:00"),
      summary: "Le four est chaud.", location: "La grange", price_text: "Prix libre",
      url: "https://example.org/inscription", attendees: 40, sales_amount_cents: 10_000,
      notes: "<div>Note interne</div>", public_description: "<div>Amenez vos ami·es.</div>",
      published_at: Time.current
    )
  end

  it "prépare une copie non enregistrée, sans dates, slug ni publication" do
    copy = described_class.new(event: source).call

    expect(copy).to be_new_record
    expect(copy.name).to eq("Pizza party")
    expect(copy.summary).to eq("Le four est chaud.")
    expect(copy.location).to eq("La grange")
    expect(copy.price_text).to eq("Prix libre")
    expect(copy.url).to eq("https://example.org/inscription")
    expect(copy.event_category).to eq(category)
    expect(copy.public_description.to_plain_text).to eq("Amenez vos ami·es.")
    expect(copy.duplicate_of_id).to eq(source.id)

    expect(copy.starts_at).to be_nil
    expect(copy.ends_at).to be_nil
    expect(copy.slug).to be_nil
    expect(copy.published_at).to be_nil
    expect(copy.attendees).to be_nil
    expect(copy.sales_amount_cents).to be_nil
    expect(copy.notes).to be_blank
    expect(Event.count).to eq(1)
  end

  it "reprend l'image de la source à la création de la copie" do
    png = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")
    source.image.attach(io: StringIO.new(png), filename: "affiche.png", content_type: "image/png")

    params = ActionController::Parameters.new(
      event: {
        name: "Pizza party d'octobre", event_category_id: category.id,
        starts_at_date: "2026-10-16", starts_at_time: "18:30", ends_at_date: "2026-10-16", ends_at_time: "22:00",
        duplicate_of_id: source.id.to_s
      }
    )
    service = Events::CreateService.new
    expect(service.run(params)).to be(true)

    copy = service.event.reload
    expect(copy.image).to be_attached
    expect(copy.image.blob).to eq(source.image.blob)
    expect(copy.published_at).to be_nil
  end
end
