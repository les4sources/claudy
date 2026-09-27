require "rails_helper"

# Epic #348, phase 5 — la page « Mon séjour » dit ce qui se passe et ce qu'on
# trouve sur place pendant le séjour : les événements publiés, l'épicerie, le
# disc-golf, et l'avertissement « réservez votre pain » bien en vue.
RSpec.describe "Public /sejour/:token — pendant votre séjour (epic #348, phase 5)", type: :request do
  let(:customer) { Customer.create!(email: "lea@example.com", first_name: "Léa") }
  let(:lodging)  { Lodging.create!(name: "La Hulotte", price_night_cents: 48_500) }
  let(:arrival)  { Date.current + 10 }
  let(:departure) { Date.current + 12 }
  let(:stay) do
    booking = Booking.create!(firstname: "Léa", lastname: "Martin", lodging: lodging,
                              from_date: arrival, to_date: departure, adults: 2,
                              status: "confirmed", booking_type: "lodging", price_cents: 48_500)
    Stay.create!(customer: customer, source: "manual", status: "confirmed",
                 arrival_date: arrival, departure_date: departure, total_amount_cents: 48_500)
        .tap { |s| s.stay_items.create!(bookable: booking) }
  end
  let(:category) { EventCategory.create!(name: "Fêtes", color: "amber") }

  def event(name, starts_at, published: true, **attrs)
    Event.create!({ name: name, event_category: category, starts_at: starts_at, ends_at: starts_at + 3.hours,
                    published_at: (Time.current if published) }.merge(attrs))
  end

  def page_body(locale: nil)
    get public_stay_path(stay.token, locale: locale)
    expect(response).to have_http_status(:ok)
    response.body
  end

  def position(body, marker) = body.index(%(#{marker}="true")) || raise("#{marker} absent")

  describe "« Pendant votre séjour »" do
    it "liste les événements publiés entre l'arrivée et le départ, par date, avec le lien vers le site" do
      later = event("Concert au four", departure.in_time_zone.change(hour: 11), location: "La grange")
      sooner = event("Balade des plantes sauvages", arrival.in_time_zone.change(hour: 18, min: 30), location: "Le verger")

      body = page_body
      section = Nokogiri::HTML(body).at_css("[data-stay-events]")
      expect(section.css("[data-stay-event]").map { |li| li["data-stay-event"].to_i }).to eq([sooner.id, later.id])
      expect(section.text).to include("Pendant votre séjour", "Balade des plantes sauvages", "Le verger", "18:30")
      expect(section.at_css("a[href='https://www.les4sources.be/evenements/#{sooner.slug}']")).to be_present
    end

    it "ignore les brouillons et ce qui tombe hors du séjour" do
      event("Brouillon", arrival.in_time_zone.change(hour: 18), published: false)
      event("La veille", (arrival - 1).in_time_zone.change(hour: 20))
      event("Le lendemain", (departure + 1).in_time_zone.change(hour: 10))

      expect(page_body).not_to include("data-stay-events", "Brouillon", "La veille", "Le lendemain")
    end

    it "se place après les activités et avant le total" do
      event("Balade", arrival.in_time_zone.change(hour: 18))
      body = page_body
      expect(position(body, "data-stay-events")).to be < position(body, "data-stay-total")
    end
  end

  it "montre la boulangerie, l'épicerie puis le disc-golf, dans cet ordre, avant le contact" do
    body = page_body
    bakery = position(body, "data-stay-bakery")
    grocery = position(body, "data-stay-grocery")
    disc_golf = position(body, "data-stay-disc-golf")

    expect(bakery).to be < grocery
    expect(grocery).to be < disc_golf
    expect(disc_golf).to be < body.index(I18n.t("public.stays.show.contact_us_heading", locale: :fr))
    expect(body).to include("pâtes et riz en vrac", "muesli", "jus de pommes", "Disc Golf Attitude",
                            %(href="https://www.discgolfattitude.be"))
  end

  it "met l'avertissement « réservez votre pain » en évidence" do
    advance = Nokogiri::HTML(page_body).at_css("[data-stay-bakery] [data-stay-bakery-advance] span")
    expect(advance.text.strip).to eq(I18n.t("public.stays.bakery.advance", locale: :fr))
    expect(advance["class"]).to include("font-semibold", "rounded-full")
  end

  %w[en nl].each do |locale|
    it "est traduite en #{locale}, sans clé manquante" do
      event("Balade", arrival.in_time_zone.change(hour: 18))
      body = page_body(locale: locale)
      expect(body).not_to include("translation missing")
      expect(body).to include(I18n.t("public.stays.grocery.heading", locale: locale).gsub("'", "&#39;"),
                              I18n.t("public.stays.disc_golf.heading", locale: locale),
                              I18n.t("public.stays.events.heading", locale: locale))
    end
  end
end
