import { Composition, Still } from "remotion";
import { Promo, Thumbnail } from "./Composition";

export const RemotionRoot = () => (
  <>
    <Composition
      id="TheCallPromo"
      component={Promo}
      width={1080}
      height={1350}
      fps={30}
      durationInFrames={631}
    />
    <Still
      id="TheCallThumbnail"
      component={Thumbnail}
      width={1080}
      height={1350}
    />
  </>
);
