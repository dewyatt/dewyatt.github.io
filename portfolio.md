---
layout: page
title: Portfolio
permalink: /portfolio/
---

Open-Source Projects
========

{% for project in site.data.portfolio.projects %}
<div class="project">{% img {{project.image}}|{{project.thumbnail}} %}
  <h4>{{ project.name }}</h4>
  <p class="project-description">{{ project.description }}</p>
  <div class="download">
    {% for link in project.links %}
      <a href='{{ link.url }}' class='icon-{{ link.icon }}'>{{ link.name }}</a>
    {% endfor %}
  </div>
</div>
{% endfor %}

Open-Source Contributions
=========================

{% for project in site.data.portfolio.majorcontribs %}
<div class="project">{% img {{project.image}}|{{project.thumbnail}} %}
  <h4>{{ project.name }}</h4>
  <p class="project-description">{{ project.description }}</p>
  <div class="download">
    {% for link in project.links %}
      <a href='{{ link.url }}' class='icon-{{ link.icon }}'>{{ link.name }}</a>
    {% endfor %}
  </div>
</div>
{% endfor %}

Other Minor Contributions
=========================

Contributed bug fixes to the following projects:

{% for project in site.data.portfolio.minorcontribs %}* {{ project.name }}
{% endfor %}
