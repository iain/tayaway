# frozen_string_literal: true

RSpec.shared_examples "a pool object" do |expected_client_type|
  it "emits a string id" do
    expect(subject[:id]).to be_a(String)
    expect(subject[:id]).not_to be_empty
  end

  it "emits objectType #{expected_client_type}" do
    expect(subject[:objectType]).to eq(expected_client_type)
  end

  it "emits an iso8601(3) updatedAt" do
    expect(subject[:updatedAt]).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}/)
  end
end

RSpec.shared_examples "a pool object with createdAt" do |expected_client_type|
  it_behaves_like "a pool object", expected_client_type

  it "emits an iso8601(3) createdAt" do
    expect(subject[:createdAt]).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}/)
  end
end
