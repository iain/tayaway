# frozen_string_literal: true

require "spec_helper"

RSpec.describe IcsGenerator do
  let(:base_params) do
    {
      uid: "event-123",
      summary: "Summer Trip",
      start_date: Date.new(2026, 3, 10),
      end_date: Date.new(2026, 3, 12),
      created_at: Time.utc(2026, 2, 1, 12, 0, 0)
    }
  end

  it "produces a valid VCALENDAR structure" do
    ics = described_class.generate(**base_params)

    expect(ics).to include("BEGIN:VCALENDAR")
    expect(ics).to include("VERSION:2.0")
    expect(ics).to include("PRODID:-//Tayaway//Tayaway//EN")
    expect(ics).to include("CALSCALE:GREGORIAN")
    expect(ics).to include("METHOD:PUBLISH")
    expect(ics).to include("BEGIN:VEVENT")
    expect(ics).to include("END:VEVENT")
    expect(ics).to include("END:VCALENDAR")
  end

  it "sets UID with @tayaway suffix" do
    ics = described_class.generate(**base_params)

    expect(ics).to include("UID:event-123@tayaway")
  end

  it "sets SUMMARY from the event name" do
    ics = described_class.generate(**base_params)

    expect(ics).to include("SUMMARY:Summer Trip")
  end

  it "uses VALUE=DATE for all-day DTSTART" do
    ics = described_class.generate(**base_params)

    expect(ics).to include("DTSTART;VALUE=DATE:20260310")
  end

  it "uses exclusive DTEND (end_date + 1 day)" do
    ics = described_class.generate(**base_params)

    expect(ics).to include("DTEND;VALUE=DATE:20260313")
  end

  it "handles single-day events with exclusive DTEND" do
    params = base_params.merge(start_date: Date.new(2026, 5, 1), end_date: Date.new(2026, 5, 1))
    ics = described_class.generate(**params)

    expect(ics).to include("DTSTART;VALUE=DATE:20260501")
    expect(ics).to include("DTEND;VALUE=DATE:20260502")
  end

  it "formats CREATED timestamp" do
    ics = described_class.generate(**base_params)

    expect(ics).to include("CREATED:20260201T120000Z")
  end

  it "escapes backslashes, semicolons, commas, and newlines in summary" do
    params = base_params.merge(summary: "Trip\\to;the,beach\nparty")
    ics = described_class.generate(**params)

    expect(ics).to include("SUMMARY:Trip\\\\to\\;the\\,beach\\nparty")
  end

  it "includes DESCRIPTION when provided" do
    ics = described_class.generate(**base_params.merge(description: "Pack your bags"))

    expect(ics).to include("DESCRIPTION:Pack your bags")
  end

  it "includes LOCATION when provided" do
    ics = described_class.generate(**base_params.merge(location: "Barcelona, Spain"))

    expect(ics).to include("LOCATION:Barcelona\\, Spain")
  end

  it "omits DESCRIPTION when nil" do
    ics = described_class.generate(**base_params)

    expect(ics).not_to include("DESCRIPTION")
  end

  it "omits LOCATION when nil" do
    ics = described_class.generate(**base_params)

    expect(ics).not_to include("LOCATION")
  end

  it "folds lines longer than 75 octets" do
    long_summary = "A" * 100
    ics = described_class.generate(**base_params.merge(summary: long_summary))

    ics.split("\r\n").each do |line|
      next if line.start_with?(" ") # continuation lines are prefixed with space

      expect(line.bytesize).to be <= 75
    end
  end

  it "uses CRLF line endings" do
    ics = described_class.generate(**base_params)

    # Every line break should be \r\n, not bare \n
    expect(ics).not_to match(/[^\r]\n/)
  end
end
