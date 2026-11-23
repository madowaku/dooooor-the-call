import type { CSSProperties } from "react";
import { Audio, Video } from "@remotion/media";
import {
  AbsoluteFill,
  Img,
  Sequence,
  staticFile,
  useVideoConfig,
} from "remotion";
import "./promo.css";

const footage: CSSProperties = {
  position: "absolute",
  left: 24,
  top: 288,
  width: 1032,
  height: 774,
};

const media = (filename: string) => staticFile(`media/${filename}`);

const GameFont = () => (
  <style>{`@font-face { font-family: DotGothic16; src: url("${media("DotGothic16-Regular.ttf")}") format("truetype"); font-display: block; }`}</style>
);

// Recorded sound stays with each take. Short edge ramps keep hard picture cuts clean.
const clipGain = (gain: number, length: number) => (frame: number) =>
  gain * Math.max(0, Math.min(1, (frame + 1) / 2, (length - frame - 1) / 3));

const Logo = () => (
  <div className="game-logo" aria-label="DOOOOOR: THE CALL">
    <Img src={media("logo_main.png")} className="logo-main" />
    <Img src={media("logo_sub.png")} className="logo-sub" />
  </div>
);

const GameAddress = () => (
  <div className="game-address">madowaku.itch.io/dooooor-the-call</div>
);

export const Promo = () => {
  const { fps } = useVideoConfig();

  return (
    <AbsoluteFill className="archive">
      <GameFont />
      <div className="screen-rim" style={footage} />
      <Video
        name="Black telephone"
        src={media("phone.mp4")}
        from={0}
        trimBefore={0}
        durationInFrames={48}
        premountFor={fps}
        volume={0.8}
        style={footage}
      />
      <Audio
        name="Opening bell · original game asset"
        src={media("bell_ring.wav")}
        from={0}
        durationInFrames={48}
        premountFor={fps}
        volume={clipGain(0.57, 48)}
      />
      <Video
        name="Hall to door 1"
        src={media("first-door.mp4")}
        from={48}
        trimBefore={25}
        durationInFrames={64}
        premountFor={fps}
        volume={clipGain(1.12, 64)}
        style={footage}
      />
      <Video
        name="Door 1 · face without a socket"
        src={media("blank-face.mp4")}
        from={112}
        trimBefore={0}
        durationInFrames={20}
        premountFor={fps}
        volume={clipGain(1.03, 20)}
        style={footage}
      />
      <Video
        name="Empty knob socket"
        src={media("first-door.mp4")}
        from={132}
        trimBefore={115}
        durationInFrames={20}
        premountFor={fps}
        volume={clipGain(1.12, 20)}
        style={footage}
      />
      <Video
        name="Knob from the pocket"
        src={media("first-door.mp4")}
        from={152}
        trimBefore={187}
        durationInFrames={73}
        premountFor={fps}
        volume={clipGain(1.12, 73)}
        style={footage}
      />
      <Video
        name="Knob goes in"
        src={media("first-door.mp4")}
        from={225}
        trimBefore={344}
        durationInFrames={24}
        premountFor={fps}
        volume={clipGain(1.12, 24)}
        style={footage}
      />
      <Video
        name="Door 1 · before, turn, after"
        src={media("first-door.mp4")}
        from={249}
        trimBefore={371}
        durationInFrames={141}
        premountFor={fps}
        volume={clipGain(0.73, 141)}
        style={footage}
      />
      <Video
        name="West hall"
        src={media("west-hall.mp4")}
        from={390}
        trimBefore={6}
        durationInFrames={45}
        premountFor={fps}
        volume={clipGain(1.1, 45)}
        style={footage}
      />
      <Video
        name="Blue tiles"
        src={media("basement.mp4")}
        from={435}
        trimBefore={7}
        durationInFrames={65}
        premountFor={fps}
        volume={clipGain(1.1, 65)}
        style={footage}
      />
      <Video
        name="Receiver lift · bell stops"
        src={media("phone.mp4")}
        from={500}
        trimBefore={137}
        durationInFrames={58}
        premountFor={fps}
        volume={clipGain(1.01, 58)}
        style={footage}
      />
      <Sequence
        name="Title and itch.io address"
        from={558}
        durationInFrames={73}
        premountFor={fps}
      >
        <AbsoluteFill className="archive end-card">
          <Logo />
          <GameAddress />
        </AbsoluteFill>
      </Sequence>
    </AbsoluteFill>
  );
};

export const Thumbnail = () => (
  <AbsoluteFill className="archive thumbnail">
    <GameFont />
    <Logo />
    <div className="screen-rim" style={{ ...footage, top: 333 }} />
    <Img src={media("phone-cover.png")} style={{ ...footage, top: 333 }} />
    <GameAddress />
  </AbsoluteFill>
);
