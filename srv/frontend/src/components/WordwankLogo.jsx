import './WordwankLogo.css';

// The Wordwank logo: the wooden W tile (assets/logo, via generate.sh) followed
// by the original wordmark, chunky Luckiest Guy in sunflower with a stacked
// orange drop shadow. Sized by `height` to match LogodalLogo's API.
const WordwankLogo = ({ height = 50, className, style }) => (
    <div
        role="img"
        aria-label="Wordwank"
        className={`wordwank-logo${className ? ` ${className}` : ''}`}
        // A custom property rather than an inline font-size, so stylesheet
        // rules (App.css's mobile header breakpoints) can still override it.
        style={{ '--wordwank-logo-size': `${height * 0.8}px`, ...style }}
    >
        <img
            className="wordwank-logo__tile"
            src="/brands/wordwank/favicon/logo-tile-256x256.png"
            alt=""
            width={height}
            height={height}
            draggable={false}
        />
        <span className="wordwank-logo__text">Wordwank</span>
    </div>
);

export default WordwankLogo;
