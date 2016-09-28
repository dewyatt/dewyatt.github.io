---
layout: page
title: Articles
permalink: /articles/
---

  <ul class="post-list">
    {% for post in site.posts %}
    {% if post.visible != false %}
      <li>
        <span class="post-meta">{{ post.date | date: "%b %-d, %Y" }}</span>

        <h2>
          <a class="post-link" href="{{ post.url | prepend: site.baseurl }}">{{ post.title | escape }}</a>
        </h2>
      </li>
    {% endif %}
    {% endfor %}
  </ul>
