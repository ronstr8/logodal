const FONT = "-apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif";

const LogodalLogo = ({ height = 50, className, style }) => (
    <svg
        xmlns="http://www.w3.org/2000/svg"
        viewBox="90 14 570 122"
        height={height}
        role="img"
        aria-label="Logodal"
        className={className}
        style={{ display: 'block', flexShrink: 0, ...style }}
    >
        <defs>
            <clipPath id="logo-tile-clip">
                <rect x="100" y="24" width="100" height="100" rx="14"/>
            </clipPath>
        </defs>

        {/* Tile shadow */}
        <rect x="104" y="30" width="100" height="100" rx="14" fill="#5A3008" opacity="0.18"/>
        {/* Tile body */}
        <rect x="100" y="24" width="100" height="100" rx="14" fill="#CC904C"/>
        {/* Diagonal grain lines */}
        <g clipPath="url(#logo-tile-clip)" stroke="#7A4C10" strokeWidth="16" opacity="0.14">
            <line x1="60"  y1="24" x2="200" y2="164"/>
            <line x1="80"  y1="24" x2="220" y2="164"/>
            <line x1="100" y1="24" x2="240" y2="164"/>
            <line x1="120" y1="24" x2="260" y2="164"/>
            <line x1="140" y1="24" x2="280" y2="164"/>
            <line x1="160" y1="24" x2="300" y2="164"/>
        </g>
        {/* Top-edge highlight */}
        <rect x="102" y="26" width="96" height="5" rx="2" fill="#F0C07A" opacity="0.5" clipPath="url(#logo-tile-clip)"/>
        {/* Tile border */}
        <rect x="100" y="24" width="100" height="100" rx="14" fill="none" stroke="#8A5C18" strokeWidth="1.5"/>
        {/* Lambda */}
        <text x="150" y="104" fontSize="82" fontWeight="700" textAnchor="middle"
              fill="#2C1000" fontFamily={FONT}>λ</text>
        {/* Question mark */}
        <text x="197" y="116" fontSize="26" fontWeight="700" textAnchor="end"
              fill="#2C1000" fontFamily={FONT}>?</text>

        {/* Wordmark */}
        <text x="214" y="104" fontSize="82" fontWeight="700" fill="#CC904C"
              fontFamily={FONT}>LOGODAL</text>
    </svg>
);

export default LogodalLogo;
