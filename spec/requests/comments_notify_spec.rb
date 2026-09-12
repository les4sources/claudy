require "rails_helper"

# Epic #242, phase 2 — poster un commentaire prévient les gens concernés. Le
# contrôleur ne fabrique rien lui-même : il délègue à
# `Notifications::CommentPosted` (décision 2).
RSpec.describe "Commentaires — notification des destinataires (epic #242, Phase 2)", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  let(:michael) { User.create!(email: "michael-comm@les4sources.be", password: "password123") }
  let(:compta)  { User.create!(email: "compta-comm@les4sources.be", password: "password123") }

  let!(:category) { GatheringCategory.create!(name: "Collectif", color: "#0B3D3A") }
  let(:gathering) do
    Gathering.create!(gathering_category: category,
                      starts_at: Time.zone.parse("2026-03-03 18:00"),
                      ends_at: Time.zone.parse("2026-03-03 20:00"))
  end

  before { ActionMailer::Base.deliveries.clear }

  def post_comment(as:, body:)
    sign_in as
    post comments_path, params: {
      comment: { commentable_type: "Gathering", commentable_id: gathering.id, body: body }
    }
  end

  it "allume la cloche du premier auteur quand on lui répond" do
    post_comment(as: michael, body: "Premier mot")

    perform_enqueued_jobs { post_comment(as: compta, body: "Il manque le ticket du 12/08") }

    notification = michael.notifications.last
    expect(notification).to be_present
    expect(notification.kind).to eq("comment")
    expect(notification.url).to start_with("/gatherings/#{gathering.id}#comment-")
    expect(ActionMailer::Base.deliveries.map(&:to).flatten).to include(michael.email)
  end

  it "ne notifie pas l'auteur du commentaire" do
    post_comment(as: michael, body: "Un mot")
    post_comment(as: michael, body: "Un autre mot")

    expect(Notification.count).to be_zero
  end

  it "ne notifie rien quand le commentaire est refusé" do
    post_comment(as: michael, body: "Premier mot")

    sign_in compta
    post comments_path, params: {
      comment: { commentable_type: "Gathering", commentable_id: gathering.id, body: "" }
    }

    # Sans Turbo, le contrôleur renvoie le navigateur d'où il venait ; ce qui
    # compte ici, c'est qu'aucun commentaire n'ait été créé, donc personne
    # prévenu.
    expect(gathering.comments.count).to eq(1)
    expect(Notification.count).to be_zero
  end
end
