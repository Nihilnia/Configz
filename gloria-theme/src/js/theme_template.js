(function () {
  const tokenReplacements = {
    'fdfdfd': "color: #fdfdfd; text-shadow: 0 0 2px #393a33, 0 0 8px #ffffff[NEON_BRIGHTNESS], 0 0 25px #ffffff[NEON_BRIGHTNESS]; backface-visibility: hidden;",
    'ff0000': "color: #ff0000; text-shadow: 0 0 2px #000000, 0 0 4px #ff0000[NEON_BRIGHTNESS], 0 0 6px #ff0000[NEON_BRIGHTNESS]; backface-visibility: hidden;",
    '1e90ff': "color: #1e90ff; text-shadow: 0 0 2px #001716, 0 0 4px #1e90ff[NEON_BRIGHTNESS], 0 0 8px #1e90ff[NEON_BRIGHTNESS]; backface-visibility: hidden;"
  };

  const replaceTokens = (styles, replacements) => Object.keys(replacements).reduce((acc, color) => {
    const re = new RegExp(`color:\\s*#${color}[a-f0-9]{0,2}\\b;?`, 'gi');
    return acc.replace(re, replacements[color]);
  }, styles);

  const usingGloria = () => {
    const appliedTheme = document.querySelector('[class*="theme-json"]');
    const gloriaTheme = document.querySelector('[class*="gloria"]');
    return appliedTheme && gloriaTheme;
  }

  const initNeonDreams = (disableGlow) => {
    if (!usingGloria()) return;

    let allTokens = '';
    const tokensEls = document.querySelectorAll('.vscode-tokens-styles');
    tokensEls.forEach(el => {
      allTokens += el.innerText;
    });

    let updatedThemeStyles = !disableGlow 
      ? replaceTokens(allTokens, tokenReplacements) 
      : allTokens;
    
    updatedThemeStyles = `${updatedThemeStyles}[CHROME_STYLES]`;

    let styleTag = document.querySelector('#gloria-theme-styles');
    if (!styleTag) {
      styleTag = document.createElement('style');
      styleTag.setAttribute("id", "gloria-theme-styles");
      document.body.appendChild(styleTag);
    }
    styleTag.innerText = updatedThemeStyles.replace(/(\r\n|\n|\r)/gm, '');
  };

  let observedTokens = new Set();
  const watchForBootstrap = function(mutationsList, observer) {
    if (!usingGloria()) return;

    const tokensEls = document.querySelectorAll('.vscode-tokens-styles');
    tokensEls.forEach(el => {
      if (!observedTokens.has(el)) {
        observer.observe(el, { childList: true, characterData: true, subtree: true });
        observedTokens.add(el);
      }
    });

    initNeonDreams([DISABLE_GLOW]);
  };

  const headNode = document.querySelector('head');
  const bodyNode = document.querySelector('body');
  const observer = new MutationObserver(watchForBootstrap);
  
  if (headNode) observer.observe(headNode, { childList: true, subtree: true });
  if (bodyNode) observer.observe(bodyNode, { attributes: true, childList: true });
  
  // Initial run
  watchForBootstrap([], observer);
})();
