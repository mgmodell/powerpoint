require 'spec_helper'

RSpec.describe Powerpoint::Presentation do
  let(:png_image) { File.expand_path('../samples/images/sample_png.png', __dir__) }
  let(:jpg_image) { File.expand_path('../samples/images/sample_jpg.jpg', __dir__) }
  let(:gif_image) { File.expand_path('../samples/images/sample_gif.gif', __dir__) }

  def pptx_entry_contents(pptx_path, entry_name)
    Zip::File.open(pptx_path) { |zip_file| zip_file.read(entry_name) }
  end

  def pptx_entries(pptx_path)
    Zip::File.open(pptx_path) { |zip_file| zip_file.map(&:name) }
  end

  it 'builds a valid pptx with expected slides, relationships and media' do
    deck = described_class.new
    deck.add_intro('Deck Title', 'Deck Subtitle')
    deck.add_textual_slide('Agenda', ['Item 1', 'Item 2'])
    deck.add_pictorial_slide('Picture', png_image, x: 100, y: 200, cx: 300, cy: 400)
    deck.add_text_picture_slide('Split', jpg_image, ['Left text'])
    deck.add_picture_description_slide('Description', gif_image, ['Caption'])

    saved_path = nil
    Dir.mktmpdir do |dir|
      output = File.join(dir, 'sample.pptx')
      saved_path = deck.save(output)

      expect(saved_path).to eq(output)
      expect(File.exist?(output)).to be(true)

      entries = pptx_entries(output)
      expect(entries).to include('[Content_Types].xml')
      expect(entries).to include('ppt/presentation.xml')
      expect(entries).to include('ppt/slides/slide1.xml', 'ppt/slides/slide2.xml', 'ppt/slides/slide3.xml', 'ppt/slides/slide4.xml', 'ppt/slides/slide5.xml')
      expect(entries).to include('ppt/media/sample_png.png', 'ppt/media/sample_jpg.jpg', 'ppt/media/sample_gif.gif')
      expect(entries).not_to include(a_string_matching(/\.keep$/))

      intro_slide = pptx_entry_contents(output, 'ppt/slides/slide1.xml')
      expect(intro_slide).to include('<a:t>Deck Title</a:t>')
      expect(intro_slide).to include('<a:t>Deck Subtitle</a:t>')
      expect(intro_slide.scan('<a:normAutofit/>').size).to eq(2)

      textual_slide = pptx_entry_contents(output, 'ppt/slides/slide2.xml')
      expect(textual_slide).to include('<a:t>Agenda</a:t>')
      expect(textual_slide).to include('<a:t>Item 1</a:t>')
      expect(textual_slide).to include('<a:t>Item 2</a:t>')
      expect(textual_slide.scan('<a:normAutofit/>').size).to eq(2)

      pictorial_slide = pptx_entry_contents(output, 'ppt/slides/slide3.xml')
      expect(pictorial_slide).to include('<a:off x="100" y="200"/>')
      expect(pictorial_slide).to include('<a:ext cx="300" cy="400"/>')
      expect(pictorial_slide.scan('<a:normAutofit/>').size).to eq(1)

      split_slide = pptx_entry_contents(output, 'ppt/slides/slide4.xml')
      expect(split_slide).to include('<a:t>Split</a:t>')
      expect(split_slide).to include('<a:t>Left text</a:t>')
      expect(split_slide.scan('<a:normAutofit/>').size).to eq(2)

      description_slide = pptx_entry_contents(output, 'ppt/slides/slide5.xml')
      expect(description_slide).to include('<a:t>Description</a:t>')
      expect(description_slide).to include('<a:t>Caption</a:t>')
      expect(description_slide.scan('<a:normAutofit/>').size).to eq(2)

      content_types = pptx_entry_contents(output, '[Content_Types].xml')
      expect(content_types).to include('Extension="png"')
      expect(content_types).to include('Extension="jpg"')
      expect(content_types).to include('Extension="gif"')

      presentation_xml = pptx_entry_contents(output, 'ppt/presentation.xml')
      expect(presentation_xml.scan('<p:sldId ').size).to eq(5)
      expect(presentation_xml).to include('<p:sldSz cx="12192000" cy="6858000" type="screen16x9"/>')

      relationships_xml = pptx_entry_contents(output, 'ppt/_rels/presentation.xml.rels')
      expect(relationships_xml).to include('Target="slides/slide1.xml"')
      expect(relationships_xml).to include('Target="slides/slide5.xml"')
    end

    expect(saved_path).to end_with('.pptx')
  end

  it 'generates readable text on a widescreen slide and escapes XML content' do
    deck = described_class.new
    deck.add_textual_slide('Goals & <objectives>', ['Readable & visible'])

    Dir.mktmpdir do |dir|
      output = File.join(dir, 'widescreen.pptx')
      deck.save(output)

      presentation_xml = pptx_entry_contents(output, 'ppt/presentation.xml')
      slide_xml = pptx_entry_contents(output, 'ppt/slides/slide1.xml')
      app_xml = pptx_entry_contents(output, 'docProps/app.xml')

      expect(presentation_xml).to include('<p:sldSz cx="12192000" cy="6858000" type="screen16x9"/>')
      expect(slide_xml).to include('<a:bodyPr><a:normAutofit/></a:bodyPr>')
      expect(slide_xml).to include('Goals &amp; &lt;objectives&gt;')
      expect(slide_xml).to include('Readable &amp; visible')
      expect(app_xml).to include('<PresentationFormat>On-screen Show (16:9)</PresentationFormat>')
      expect(app_xml).to include('Goals &amp; &lt;objectives&gt;')
    end
  end

  it 'adds transitions and durations to each slide type' do
    deck = described_class.new
    deck.add_intro('Opening', 'Subtitle', transition: { type: :fade, duration: 750 })
    deck.add_textual_slide('Agenda', [], transition: { type: :wipe, duration: 1000 })
    deck.add_pictorial_slide('Picture', png_image, {}, transition: { type: :dissolve, duration: 1250 })
    deck.add_text_picture_slide('Split', png_image, [], transition: { type: :push, duration: 1500 })
    deck.add_picture_description_slide('Description', png_image, [], transition: { type: :zoom, duration: 2000 })

    Dir.mktmpdir do |dir|
      output = File.join(dir, 'transitions.pptx')
      deck.save(output)

      expected_transitions = [
        ['fade', 750],
        ['wipe', 1000],
        ['dissolve', 1250],
        ['push', 1500],
        ['zoom', 2000]
      ]

      expected_transitions.each_with_index do |(type, duration), index|
        slide_xml = pptx_entry_contents(output, "ppt/slides/slide#{index + 1}.xml")
        expect(slide_xml).to include(%(p14:dur="#{duration}"))
        expect(slide_xml).to include("<p:#{type}/>")
      end
    end
  end

  it 'rejects unsupported transitions and invalid durations' do
    deck = described_class.new
    deck.add_textual_slide('Invalid', [], transition: { type: 'unexpected' })

    Dir.mktmpdir do |dir|
      expect { deck.save(File.join(dir, 'invalid.pptx')) }.to raise_error(ArgumentError, /unsupported transition type/)
    end

    deck = described_class.new
    deck.add_textual_slide('Invalid duration', [], transition: { duration: 'fast' })

    Dir.mktmpdir do |dir|
      expect { deck.save(File.join(dir, 'invalid-duration.pptx')) }.to raise_error(ArgumentError, /duration must be a positive integer/)
    end
  end

  it 'replaces an existing intro slide and keeps it at the beginning' do
    deck = described_class.new
    deck.add_textual_slide('Body', ['one'])
    deck.add_intro('Original', 'Sub')
    deck.add_intro('Updated', 'Sub 2')

    expect(deck.slides.length).to eq(2)
    expect(deck.slides.first).to be_a(Powerpoint::Slide::Intro)
    expect(deck.slides.first.title).to eq('Updated')
    expect(deck.slides[1]).to be_a(Powerpoint::Slide::Textual)
  end

  it 'returns unique non-nil media file types' do
    deck = described_class.new
    deck.add_intro('Only title')
    deck.add_pictorial_slide('Png 1', png_image)
    deck.add_pictorial_slide('Png 2', png_image)
    deck.add_pictorial_slide('Jpg', jpg_image)

    expect(deck.file_types).to eq(%w[png jpg])
  end
end

RSpec.describe Powerpoint::Util do
  let(:dummy_class) do
    Class.new do
      include Powerpoint::Util
    end
  end
  let(:dummy) { dummy_class.new }

  it 'converts pixels to points' do
    expect(dummy.pixle_to_pt(2)).to eq(25_400)
  end

  it 'raises when required arguments are missing' do
    expect { dummy.require_arguments([:a, :b], { a: 1 }) }.to raise_error(ArgumentError)
  end

  it 'does not raise when required arguments are present' do
    expect { dummy.require_arguments([:a], { a: 1 }) }.not_to raise_error
  end

  it 'copies media only once when destination already exists' do
    Dir.mktmpdir do |dir|
      media_dir = File.join(dir, 'ppt', 'media')
      FileUtils.mkdir_p(media_dir)
      source = File.join(dir, 'source.png')
      destination = File.join(media_dir, 'source.png')

      File.write(source, 'first')
      dummy.copy_media(dir, source)
      expect(File.read(destination)).to eq('first')

      File.write(source, 'second')
      dummy.copy_media(dir, source)
      expect(File.read(destination)).to eq('first')
    end
  end

  it 'renders templates with variables' do
    Dir.mktmpdir do |dir|
      output = File.join(dir, 'rendered.xml')
      dummy.render_view('textual_rel.xml.erb', output, index: 12)
      expect(File.read(output)).to include('slideLayout12.xml')
    end
  end

  it 'reads templates from the gem views path' do
    template = dummy.read_template('app.xml.erb')
    expect(template).to include('<%= slides.length %>')
  end

  it 'merges local variables into a binding' do
    base_binding = binding
    merged_binding = dummy.merge_variables(base_binding, answer: 42)

    expect(merged_binding.local_variable_get(:answer)).to eq(42)
  end
end

RSpec.describe 'slide helpers and compression' do
  let(:png_image) { File.expand_path('../samples/images/sample_png.png', __dir__) }

  it 'uses empty default coordinates when image dimensions are unavailable' do
    slide = Powerpoint::Slide::Pictorial.new(
      presentation: Powerpoint::Presentation.new,
      title: 'Missing image',
      image_path: '/does/not/exist.png',
      coords: {}
    )

    expect(slide.coords).to eq({})
    expect(slide.file_type).to eq('png')
  end

  it 'compresses pptx directories and excludes macOS metadata files' do
    Dir.mktmpdir do |dir|
      source_dir = File.join(dir, 'source')
      output = File.join(dir, 'archive.pptx')

      FileUtils.mkdir_p(File.join(source_dir, 'nested'))
      File.write(File.join(source_dir, 'nested', 'file.txt'), 'hello')
      File.write(File.join(source_dir, '.DS_Store'), 'ignored')

      Powerpoint.compress_pptx(source_dir, output)
      expect(File.exist?(output)).to be(true)

      zip_entries = Zip::File.open(output) { |zip_file| zip_file.map(&:name) }
      expect(zip_entries).to include('nested/file.txt')
      expect(zip_entries).not_to include('.DS_Store')
    end
  end

  it 'computes non-empty default coordinates for valid images' do
    slide = Powerpoint::Slide::TextPicSplit.new(
      presentation: Powerpoint::Presentation.new,
      title: 'Split',
      image_path: png_image,
      content: ['A']
    )

    expect(slide.coords).to include(:x, :y, :cx, :cy)
    expect(slide.coords[:x]).to eq(480 * 12_700)
    expect(slide.coords[:cy]).to be <= 420 * 12_700
  end

  it 'centers default images within the widescreen canvas and available height' do
    slides = [
      [
        Powerpoint::Slide::Pictorial.new(
          presentation: Powerpoint::Presentation.new,
          title: 'Picture',
          image_path: png_image,
          coords: {}
        ),
        420
      ],
      [
        Powerpoint::Slide::DescriptionPic.new(
          presentation: Powerpoint::Presentation.new,
          title: 'Description',
          image_path: png_image,
          content: []
        ),
        300
      ]
    ]

    slides.each do |slide, max_height|
      expect(slide.coords[:x] + slide.coords[:cx] / 2).to eq(960 * 12_700 / 2)
      expect(slide.coords[:cy]).to be <= max_height * 12_700
    end
  end

  it 'constrains portrait images to the slide content height' do
    allow(FastImage).to receive(:size).and_return([100, 1_000])

    slides = [
      [
        Powerpoint::Slide::Pictorial.new(
          presentation: Powerpoint::Presentation.new,
          title: 'Picture',
          image_path: 'portrait.png',
          coords: {}
        ),
        420
      ],
      [
        Powerpoint::Slide::TextPicSplit.new(
          presentation: Powerpoint::Presentation.new,
          title: 'Split',
          image_path: 'portrait.png',
          content: []
        ),
        420
      ],
      [
        Powerpoint::Slide::DescriptionPic.new(
          presentation: Powerpoint::Presentation.new,
          title: 'Description',
          image_path: 'portrait.png',
          content: []
        ),
        300
      ]
    ]

    slides.each do |slide, max_height|
      expect(slide.coords[:cy]).to eq(max_height * 12_700)
    end
  end
end
