import './WordwankLogo.css';

// The original Wordwank wordmark: chunky Luckiest Guy in sunflower with a
// stacked orange drop shadow. Sized by `height` to match LogodalLogo's API.
const WordwankLogo = ({ height = 50, className, style }) => (
    <div
        role="img"
        aria-label="Wordwank"
        className={`wordwank-logo${className ? ` ${className}` : ''}`}
        style={{ fontSize: `${height * 0.8}px`, ...style }}
    >
        Wordwank
    </div>
);

export default WordwankLogo;
