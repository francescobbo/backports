require 'httparty'
require 'yaml'
require 'pathname'
require 'nokogiri'
require 'pry-byebug'
require 'gems'

TODO = "#{__dir__}/todo.yml"

class HtmlParserIncluded < HTTParty::Parser
  def html
    Nokogiri::HTML(body)
  end
end

class Page
  include HTTParty
  parser HtmlParserIncluded
end


def reverse_depencies(gem, n = 100)
  pages = (n-1).div(30)+1
  (1..pages).flat_map do |page|
    x = Page.get("https://rubygems.org/gems/backports/reverse_dependencies?page=#{page}")
      .css(".gems__gem__name")
      .map(&:children)
      .map(&:first)
      .map(&:text)
      .map(&:strip)
  end.first(n)
end

def scrape_google(gem_name)
  # God their official API is a steaming pile of over-architected ridiculously complicated junk
  l = Page.get("https://www.google.ca/search?q=site%3Agithub.com+#{gem_name}")
    .css('.g cite')
    .first
    .text
end

def repo(gem_name)
  info = Gems.info(gem_name)
  info['source_code_uri'] || scrape_google(gem_name)
end

def list_rev_deps(n)
  gems = reverse_depencies('backports', n)
  gems.map do |g|
    rep = repo(g)
    puts "#{g.rjust(30)}: #{rep}\n"
    [g, {repo: rep, status: :initial}]
  end.to_h
end

def save_rev_deps(n, path = TODO)
  Pathname(path).write(YAML.dump(list_rev_deps(n)))
end

def patch_file(path)
  path = Pathname(path)
  path.write(yield path.read)
end

def patch_yaml(path, &block)
  patch_file(path) { |txt| YAML.dump(YAML.load(txt).tap(&block)) }
end

def patch_gem(path)
  dir = Pathname(path).expand_path
  patch(dir + 'Gemfile') { |txt| txt + "\ngem 'backports', git: 'https://github.com/marcandre/backports.git', branch: 'introspection'\n"}
  patch_yaml(dir + '.travis.yml') do |conf|
    conf['rvm'] = conf['rvm'].sort.first(1)
  end
end

def filter_todo(lookfor)
  patch_yaml(TODO) do |list|
    list.each { |k, v| v[:status] = yield v, k if v[:status] == lookfor }
  end
end

def check_repos
  filter_todo(:initial) do |entry|
    if entry[:repo] =~ /^https?:\/\/github.com\/(\w+)\/(\w+)$/
      entry[:repo_owner] = $1
      entry[:repo_name] = $2
      :potential
    else
      :invalid_repo
    end
  end
end

def clone_repos
  filter_todo(:potential) do |entry|
    remote = "#{entry[:repo_owner]}_#{entry[:repo_name]}"
    if system([
      "git remote add #{remote} git@github.com:#{entry[:repo_owner]}/#{entry[:repo_name]}.git",
      "git fetch #{remote}",
      "git checkout -b #{entry[:repo_name]}_used #{remote}/master",
    ].join(' && '))
      :cloned
    else
      :failed_cloning
    end
  end
end