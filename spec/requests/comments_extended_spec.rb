require "rails_helper"

# Epic #242, phase 4 — les commentaires sortent de la comptabilité.
#
# Un événement se prépare à plusieurs, une décision se discute après coup, un
# créneau d'activité se négocie avec son porteur : tout ça se disait ailleurs
# que dans Claudy. Le fil « Activité récente », lui, montrait tout ce qui change
# sauf ce que les gens s'écrivent.
RSpec.describe "Commentaires étendus (epic #242, phase 4)", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:human) { Human.create!(name: "Michael", email: "michael-c4@les4sources.be", status: "active") }
  let(:user)  { User.create!(email: "michael-c4@les4sources.be", password: "password123") }
  before { sign_in user }

  def post_comment(commentable, body: "Une question.")
    post comments_path, params: {
      comment: { commentable_type: commentable.class.name,
                 commentable_id: commentable.id,
                 body: body }
    }
  end

  describe "Event" do
    let(:category) { EventCategory.create!(name: "Stage") }
    let!(:organizer) { Human.create!(name: "Lise", email: "lise-c4@les4sources.be", status: "active") }
    let!(:organizer_user) { User.create!(email: "lise-c4@les4sources.be", password: "password123", human: organizer) }
    let(:event) do
      Event.create!(name: "Stage low-tech", event_category: category,
                    starts_at: Time.current + 10.days, ends_at: Time.current + 11.days)
    end

    it "accepte un commentaire et l'affiche sur la fiche" do
      expect { post_comment(event, body: "On prévoit combien de chaises ?") }
        .to change(Comment, :count).by(1)

      get event_path(event)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("On prévoit combien de chaises ?")
    end

    it "désigne les organisateurs comme destinataires" do
      event.event_organizers.create!(human: organizer, weight: 1)

      expect(event.reload.comment_recipients).to contain_exactly(organizer_user)
    end

    it "ne prévient personne quand l'événement n'a pas d'organisateur" do
      expect(event.comment_recipients).to be_empty
    end

    it "notifie les organisateurs à la publication d'un commentaire" do
      event.event_organizers.create!(human: organizer, weight: 1)

      expect { post_comment(event) }
        .to change { Notification.where(recipient: organizer_user, kind: "comment").count }.by(1)
    end

    it "n'affiche pas le fil sous l'onglet Comptabilité" do
      post_comment(event, body: "Discussion d'organisation")

      get event_path(event, tab: "comptabilite")
      expect(response.body).not_to include("Discussion d'organisation")
    end
  end

  describe "Decision" do
    let!(:recorder) { Human.create!(name: "Malau", email: "malau-c4@les4sources.be", status: "active") }
    let!(:recorder_user) { User.create!(email: "malau-c4@les4sources.be", password: "password123", human: recorder) }
    let(:decision) do
      Decision.create!(title: "On garde le four à bois", summary: "Décidé en plénière",
                       taken_at: Date.current, recorded_by: recorder)
    end

    it "accepte un commentaire et l'affiche sur la fiche" do
      expect { post_comment(decision, body: "Qui s'occupe du bois ?") }
        .to change(Comment, :count).by(1)

      get decision_path(decision)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Qui s'occupe du bois ?")
    end

    it "désigne celui qui a consigné la décision comme destinataire" do
      expect(decision.comment_recipients).to contain_exactly(recorder_user)
    end
  end

  describe "ExperienceBooking" do
    let!(:carrier) { Human.create!(name: "Porteuse", email: "porteuse-c4@les4sources.be", status: "active") }
    let!(:carrier_user) { User.create!(email: "porteuse-c4@les4sources.be", password: "password123", human: carrier) }
    let(:experience) { Experience.create!(name: "Balade ânes", human: carrier, fixed_price_cents: 3_000, price_cents: 0) }
    let(:availability) do
      ExperienceAvailability.create!(experience: experience, available_on: Date.current + 5, starts_at: "10:00")
    end
    let(:customer) { Customer.create!(email: "client-c4@example.com", first_name: "Jo", last_name: "Client") }
    let(:stay) do
      Stay.create!(customer: customer, status: "confirmed",
                   arrival_date: Date.current + 4, departure_date: Date.current + 6)
    end
    let(:booking) do
      stay.experience_bookings.create!(experience_availability: availability,
                                       participants: 2, status: "confirmed")
    end

    it "sert une fiche admin dédiée" do
      get experience_booking_path(booking)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Balade ânes")
    end

    it "accepte un commentaire et l'affiche sur la fiche" do
      expect { post_comment(booking, body: "On peut décaler à 11h ?") }
        .to change(Comment, :count).by(1)

      get experience_booking_path(booking)
      expect(response.body).to include("On peut décaler à 11h ?")
    end

    it "désigne le porteur de l'activité comme destinataire" do
      expect(booking.comment_recipients).to contain_exactly(carrier_user)
    end

    it "ne prévient personne quand l'activité n'a pas de porteur" do
      orpheline = Experience.create!(name: "Activité orpheline", fixed_price_cents: 1_000, price_cents: 0)
      slot = ExperienceAvailability.create!(experience: orpheline, available_on: Date.current + 5, starts_at: "14:00")
      sans_porteur = stay.experience_bookings.create!(experience_availability: slot,
                                                      participants: 1, status: "confirmed")

      expect(sans_porteur.comment_recipients).to be_empty
    end
  end

  describe "la page « Activité récente »" do
    let(:category) { EventCategory.create!(name: "Stage") }
    let(:event) do
      Event.create!(name: "Stage low-tech", event_category: category,
                    starts_at: Time.current + 10.days, ends_at: Time.current + 11.days)
    end

    it "montre les commentaires récents, avec un lien vers l'objet commenté" do
      post_comment(event, body: "Il manque une rallonge.")

      get recent_activity_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Il manque une rallonge.")
      expect(response.body).to include("a commenté")
    end

    it "ne remonte pas une simple correction du commentaire" do
      post_comment(event, body: "Première version.")
      comment = Comment.last

      expect {
        patch comment_path(comment), params: { comment: { body: "Version corrigée." } }
      }.not_to change { PublicActivity::Activity.where(trackable: comment).count }
    end

    it "survit à un commentaire supprimé depuis" do
      post_comment(event, body: "À oublier.")
      Comment.last.soft_delete!

      get recent_activity_path

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("À oublier.")
    end
  end
end
