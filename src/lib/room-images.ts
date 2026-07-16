import roomStandard from "@/assets/room-standard.jpg";
import roomDeluxe from "@/assets/room-deluxe.jpg";
import roomExecutive from "@/assets/room-executive.jpg";

export function roomImage(slug: string): string {
  switch (slug) {
    case "room-deluxe":
      return roomDeluxe;
    case "room-executive":
      return roomExecutive;
    default:
      return roomStandard;
  }
}
