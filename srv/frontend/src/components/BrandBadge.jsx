import { BRANDS } from '../brand';
import './BrandBadge.css';

// Tiny brand mark beside a player's name, so mixed tables show who came from
// which site. Renders nothing for an unknown/missing brand (e.g. old history).
const BrandBadge = ({ brand }) => {
    const b = brand && BRANDS[brand];
    if (!b || !b.badge) return null;
    return (
        <img
            className="brand-badge"
            src={b.badge}
            alt={b.name}
            title={b.name}
            width="16"
            height="16"
            draggable="false"
        />
    );
};

export default BrandBadge;
