#' @rdname hook_plot
#' @export
hook_plot_md = function(x, options) {
  # if not using R Markdown v2 or output is HTML, just return v1 output
  if (is.null(to <- pandoc_to()) || is_html_output(to))
    return(hook_plot_md_base(x, options))
  if (!is.null(options$out.width) || !is.null(options$out.height) ||
      !is.null(options$out.extra) || options$fig.align != 'default' ||
      !is.null(options$fig.subcap)) {
    if (to %in% c('beamer', 'latex')) {
      # Pandoc < 1.13 does not support \caption[]{} so suppress short caption
      if (is.null(options$fig.scap)) options$fig.scap = NA
      return(hook_plot_tex(x, options))
    }
    if (to == 'docx') {
      warning('Chunk options fig.align, out.width, out.height, out.extra ',
              'are not supported for Word output')
      options$out.width = options$out.height = options$out.extra = NULL
      options$fig.align = 'default'
    }
  }
  if (options$fig.show == 'hold' && to == 'docx') {
    warning('The chunk option fig.show="hold" is not supported for Word output')
    options$fig.show = 'asis'
  }
  hook_plot_md_base(x, options)
}

hook_plot_md_base = function(x, options) {
  if (options$fig.show == 'animate') return(hook_plot_html(x, options))

  base = opts_knit$get('base.url') %n% ''
  cap = .img.cap(options)
  alt = .img.cap(options, alt = TRUE)

  w = options[['out.width']]; h = options[['out.height']]
  s = options$out.extra; a = options$fig.align
  ai = options$fig.show == 'asis'
  lnk = options$fig.link
  pandoc_html = cap != '' && is_html_output()
  in_bookdown = isTRUE(opts_knit$get('bookdown.internal.label'))
  plot1 = ai || options$fig.cur <= 1L
  plot2 = ai || options$fig.cur == options$fig.num
  if (is.null(w) && is.null(h) && is.null(s) && a == 'default' && !(pandoc_html && in_bookdown)) {
    # append <!-- --> to ![]() to prevent the figure environment in these cases
    nocap = cap == '' && !is.null(to <- pandoc_to()) && !grepl('^markdown', to) &&
      (options$fig.num == 1 || ai) && !grepl('-implicit_figures', pandoc_from())
    res = sprintf('![%s](%s%s)', cap, base, .upload.url(x))
    if (!is.null(lnk) && !is.na(lnk)) res = sprintf('[%s](%s)', res, lnk)
    res = paste0(res, if (nocap) '<!-- -->' else '', if (is_latex_output()) ' ' else '')
    return(res)
  }
  add_link = function(x) {
    if (is.null(lnk) || is.na(lnk)) return(x)
    sprintf('<a href="%s" target="_blank">%s</a>', lnk, x)
  }
  # use HTML syntax <img src=...>
  if (pandoc_html) {
    d1 = if (plot1) sprintf('<div class="figure"%s>\n', css_text_align(a))
    d2 = sprintf('<p class="caption">%s</p>', cap)
    img = sprintf(
      '<img src="%s" alt="%s" %s />',
      paste0(opts_knit$get('base.url'), .upload.url(x)), alt, .img.attr(w, h, s)
    )
    img = add_link(img)
    # whether to place figure caption at the top or bottom of a figure
    if (isTRUE(options$fig.topcaption)) {
      paste0(d1, if (ai || options$fig.cur <= 1) d2, img, if (plot2) '</div>')
    } else {
      paste0(d1, img, if (plot2) paste0('\n', d2, '\n</div>'))
    }
  } else add_link(.img.tag(
    .upload.url(x), w, h, alt,
    c(s, sprintf('style="%s"', css_align(a)))
  ))
}

css_align = function(align) {
  sprintf('display: block; margin: %s;', switch(
    align, left = 'auto auto auto 0', center = 'auto', right = 'auto 0 auto auto'
  ))
}

css_text_align = function(align) {
  if (align == 'default') '' else sprintf(' style="text-align: %s"', align)
}

# helper function to manage HTML classes; turn "a b" to "{.a .b}" for Pandoc
# fenced code blocks
block_class = function(x){
  if (length(x) == 0) return()
  classes = unlist(strsplit(x, '\\s+'))
  .classes = paste0('.', classes, collapse = ' ')
  paste0('{', .classes, '}')
}

#' @rdname output_hooks
#' @export
#' @param strict Boolean; whether to use strict markdown or reST syntax. For markdown, if
#'   \code{TRUE}, code blocks will be indented by 4 spaces, otherwise they are
#'   put in fences made by three backticks. For reST, if \code{TRUE}, code is
#'   put under two colons and indented by 4 spaces, otherwise it is put under the
#'   \samp{sourcecode} directive (this is useful for e.g. Sphinx).
#' @param fence_char A single character to be used in the code blocks fence.
#'   This can be e.g. a backtick or a tilde, depending on your Markdown rendering
#'   engine.
render_markdown = function(strict = FALSE, fence_char = '`') {
  set_html_dev()
  opts_knit$set(out.format = 'markdown')
  fence = paste(rep(fence_char, 3), collapse = '')
  # four spaces lead to <pre></pre>
  hook.t = function(x, options, class = NULL) {
    # this code-block duplicated from hook.t()
    if (strict) {
      paste('\n', indent_block(x), '', sep = '\n')
    } else {
      x = paste(c('', x), collapse = '\n')
      r = paste0('\n', fence_char, '{3,}')
      if (grepl(r, x)) {
        l = attr(gregexpr(r, x)[[1]], 'match.length')
        l = max(l)
        if (l >= 4) fence = paste(rep(fence_char, l), collapse = '')
      }
      paste0('\n\n', fence, block_class(class), x, fence, '\n\n')
    }
  }
  hook.o = function(x, options) {
    hook.t(x, options, options$class.output)
  }
  hook.r = function(x, options) {
    language = tolower(options$engine)
    if (language == 'node') language = 'javascript'
    if (!options$highlight) language = 'text'
    if (!is.null(options$class.source)) {
      language = block_class(c(language, options$class.source))
    }
    paste0('\n\n', fence, language, '\n', x, fence, '\n\n')
  }
  knit_hooks$set(
    source = function(x, options) {
      x = hilight_source(x, 'markdown', options)
      (if (strict) hook.t else hook.r)(paste(c(x, ''), collapse = '\n'), options)
    },
    output = hook.o, warning = hook.t, error = hook.t, message = hook.t,
    inline = function(x) {
      fmt = pandoc_to()
      fmt = if (length(fmt) == 1L) 'latex' else 'html'
      .inline.hook(format_sci(x, fmt))
    },
    plot = hook_plot_md,
    chunk = function(x, options) {
      x = gsub(paste0('[\n]{2,}(', fence, '|    )'), '\n\n\\1', x)
      x = gsub('[\n]+$', '', x)
      x = gsub('^[\n]+', '\n', x)
      if (isTRUE(options$collapse)) {
        x = gsub(paste0('\n([', fence_char, ']{3,})\n+\\1(', tolower(options$engine), ')?\n'), "\n", x)
      }
      if (is.null(s <- options$indent)) return(x)
      line_prompt(x, prompt = s, continue = s)
    }
  )
}
#' @param highlight Which code highlighting engine to use: if \code{pygments},
#'   the Liquid syntax is used (default approach Jekyll); if \code{prettify},
#'   the output is prepared for the JavaScript library \file{prettify.js}; if
#'   \code{none}, no highlighting engine will be used, and code blocks are simply
#'   indented by 4 spaces).
#' @param extra Extra tags for the highlighting engine. For \code{pygments}, this
#'   can be \code{'linenos'}; for \code{prettify}, it can be \code{'linenums'}.
#' @rdname output_hooks
#' @export
render_jekyll = function(highlight = c('pygments', 'prettify', 'none'), extra = '') {
  hi = match.arg(highlight)
  render_markdown(TRUE)
  if (hi == 'none') return()
  switch(hi, pygments = {
    hook.r = function(x, options) {
      paste0(
        '\n\n{% highlight ', tolower(options$engine), if (extra != '') ' ', extra,
        ' %}\n', x, '\n{% endhighlight %}\n\n'
      )
    }
    hook.t = function(x, options) paste0(
      '\n\n{% highlight text %}\n', x, '{% endhighlight %}\n\n'
    )
  }, prettify = {
    hook.r = function(x, options) {
      paste0(
        '\n\n<pre><code class="prettyprint ', extra, '">', escape_html(x),
        '</code></pre>\n\n'
      )
    }
    hook.t = function(x, options) paste0(
      '\n\n<pre><code>', escape_html(x), '</code></pre>\n\n'
    )
  })
  knit_hooks$set(source = function(x, options) {
    x = paste(hilight_source(x, 'markdown', options), collapse = '\n')
    hook.r(x, options)
  }, output = hook.t, warning = hook.t, error = hook.t, message = hook.t)
}
