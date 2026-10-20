require "rails_helper"

# « À faire » rappelle les PDF des frais Stripe (Michael, 2026-10-19) : Stripe
# les met à disposition au plus tard le 10 du mois suivant, et ne les expose
# pas par l'API.
RSpec.describe Finance::AccountingTodo, "justificatifs Stripe" do
  def item(today)
    described_class.new(today: today).items.find { |i| i.label == "Déposer les justificatifs Stripe" }
  end

  before do
    StripeFeeInvoice.create!(account_key: "claudy", period_month: Date.new(2026, 8, 1), declared_fee_cents: 3_000)
    StripeFeeInvoice.create!(account_key: "claudy", period_month: Date.new(2026, 9, 1), declared_fee_cents: 4_210)
  end

  it "ne réclame pas le mois précédent avant le 10" do
    todo = item(Date.new(2026, 10, 9))
    expect(todo.count).to eq(1)
    expect(todo.detail).to include("août")
    expect(todo).to be_todo
  end

  it "réclame le mois précédent à partir du 10" do
    expect(item(Date.new(2026, 10, 10)).count).to eq(2)
  end

  it "passe à fait quand chaque mois a son PDF" do
    StripeFeeInvoice.find_each do |invoice|
      invoice.document.attach(io: StringIO.new("%PDF-1.4"), filename: "stripe.pdf", content_type: "application/pdf")
    end

    todo = item(Date.new(2026, 10, 19))
    expect(todo).to be_done
    expect(todo.path).to include("from=2026-01-01")
  end
end
