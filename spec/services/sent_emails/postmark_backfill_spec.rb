require "rails_helper"

# Rapatriement de l'historique Postmark. L'API est doublée : on vérifie le
# contrat (recherche paginée + détail par message), pas Postmark lui-même.
RSpec.describe SentEmails::PostmarkBackfill do
  let!(:customer) do
    Customer.create!(email: "cliente@example.com", customer_type: "individual",
                     first_name: "Ada", last_name: "Lovelace")
  end

  # Forme réelle d'une entrée de « outbound message search » : clés de premier
  # niveau en symboles underscore, structures imbriquées en CamelCase.
  def search_entry(message_id:, to: "cliente@example.com", subject: "Votre séjour", tag: "booking_confirmed")
    {
      message_id: message_id,
      to: [{ "Email" => to, "Name" => nil }],
      recipients: [to],
      received_at: "2026-07-20T09:30:00-05:00",
      subject: subject,
      tag: tag,
      status: "Sent"
    }
  end

  def details(html: "<p>Bonjour Ada</p>", text: "Bonjour Ada")
    { html_body: html, text_body: text }
  end

  let(:client) { instance_double(Postmark::ApiClient) }

  def stub_search(pages)
    allow(client).to receive(:get_messages) do |options|
      pages[options[:offset]] || []
    end
  end

  subject(:backfill) { described_class.new(days: 45, throttle: 0, client: client) }

  it "importe les emails adressés à un client, avec sujet, corps et date" do
    stub_search(0 => [search_entry(message_id: "pm-1")])
    allow(client).to receive(:get_message).with("pm-1").and_return(details)

    stats = backfill.run

    expect(stats[:imported]).to eq(1)
    sent = SentEmail.last
    expect(sent.customer).to eq(customer)
    expect(sent.subject).to eq("Votre séjour")
    expect(sent.body_html).to eq("<p>Bonjour Ada</p>")
    expect(sent.body_text).to eq("Bonjour Ada")
    expect(sent.tag).to eq("booking_confirmed")
    expect(sent.source).to eq("postmark")
    expect(sent.postmark_message_id).to eq("pm-1")
    expect(sent.sent_at).to eq(Time.zone.parse("2026-07-20T09:30:00-05:00"))
  end

  it "ignore les messages dont le destinataire n'est pas un client" do
    stub_search(0 => [search_entry(message_id: "pm-2", to: "equipe@les4sources.be")])

    stats = backfill.run

    expect(stats[:unmatched]).to eq(1)
    expect(SentEmail.count).to eq(0)
    # Aucun appel de détail gaspillé sur un message hors périmètre.
    expect(client).not_to have_received(:get_message) if client.respond_to?(:get_message)
  end

  it "est rejouable : un message déjà journalisé n'est pas ré-importé" do
    SentEmail.create!(customer: customer, to_email: customer.email, subject: "Déjà là",
                      sent_at: 1.day.ago, postmark_message_id: "pm-3", source: "app")
    stub_search(0 => [search_entry(message_id: "pm-3")])

    expect { backfill.run }.not_to change(SentEmail, :count)
    expect(backfill.stats[:skipped]).to eq(1)
  end

  it "parcourt les pages suivantes tant que Postmark en renvoie" do
    page_1 = Array.new(100) { |i| search_entry(message_id: "pm-a#{i}") }
    stub_search(0 => page_1, 100 => [search_entry(message_id: "pm-b")])
    allow(client).to receive(:get_message).and_return(details)

    stats = backfill.run

    expect(stats[:scanned]).to eq(101)
    expect(SentEmail.count).to eq(101)
  end

  it "respecte le plafond de messages parcourus" do
    stub_search(0 => Array.new(5) { |i| search_entry(message_id: "pm-c#{i}") })
    allow(client).to receive(:get_message).and_return(details)

    stats = described_class.new(limit: 3, throttle: 0, client: client).run

    expect(stats[:scanned]).to eq(3)
  end

  it "importe quand même un message dont le contenu a expiré chez Postmark" do
    stub_search(0 => [search_entry(message_id: "pm-4")])
    allow(client).to receive(:get_message).with("pm-4").and_return(details(html: nil, text: nil))

    stats = backfill.run

    expect(stats[:without_body]).to eq(1)
    expect(SentEmail.last.body_html).to be_nil
    expect(SentEmail.last.subject).to eq("Votre séjour")
  end

  it "n'écrit rien en DRY_RUN" do
    stub_search(0 => [search_entry(message_id: "pm-5")])
    allow(client).to receive(:get_message).and_return(details)

    expect { described_class.new(dry_run: true, throttle: 0, client: client).run }
      .not_to change(SentEmail, :count)
  end

  it "poursuit le parcours si le détail d'un message est indisponible" do
    stub_search(0 => [search_entry(message_id: "pm-6")])
    allow(client).to receive(:get_message).and_raise(Postmark::ApiInputError.new("nope", {}))

    expect { backfill.run }.to change(SentEmail, :count).by(1)
    expect(SentEmail.last.body_html).to be_nil
  end
end
