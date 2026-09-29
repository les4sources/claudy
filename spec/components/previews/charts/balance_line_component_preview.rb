# @label Courbe de trésorerie
class Charts::BalanceLineComponentPreview < ViewComponent::Preview
  Point = Struct.new(:date, :balance_cents, keyword_init: true)

  TODAY = Date.new(2026, 9, 29)

  # Un an de solde réel, puis trois mois projetés.
  def with_data
    render Charts::BalanceLineComponent.new(history: history, projection: projection, today: TODAY)
  end

  # Une projection qui passe sous zéro.
  def below_zero
    dip = projection.dup
    dip.insert(2, Point.new(date: TODAY + 20, balance_cents: -120_000))
    render Charts::BalanceLineComponent.new(history: history, projection: dip, today: TODAY)
  end

  def empty
    render Charts::BalanceLineComponent.new(history: [], projection: [], today: TODAY)
  end

  private

  def history
    (0..52).map do |week|
      date = TODAY - ((52 - week) * 7)
      Point.new(date: date, balance_cents: 800_000 + (Math.sin(week / 5.0) * 350_000).round)
    end
  end

  def projection
    [
      Point.new(date: TODAY, balance_cents: history.last.balance_cents),
      Point.new(date: TODAY + 9, balance_cents: history.last.balance_cents + 250_000),
      Point.new(date: TODAY + 30, balance_cents: history.last.balance_cents - 90_000),
      Point.new(date: TODAY + 90, balance_cents: history.last.balance_cents - 90_000)
    ]
  end
end
