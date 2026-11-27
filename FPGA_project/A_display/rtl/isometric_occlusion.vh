wire occ0 = (gu >= 15'sd60) && (gu <= 15'sd208) &&
 (gv >= 15'sd60) && (gv <= 15'sd196) &&
 ((gu-gv) <= 15'sd96) && ((gv-gu) <= 15'sd84);
wire occ1 = (gu >= 15'sd248) && (gu <= 15'sd400) &&
 (gv >= 15'sd56) && (gv <= 15'sd196) &&
 ((gu-gv) <= 15'sd288) && ((gv-gu) <= -15'sd108);
wire occ2 = (gu >= 15'sd62) && (gu <= 15'sd208) &&
 (gv >= 15'sd254) && (gv <= 15'sd388) &&
 ((gu-gv) <= -15'sd96) && ((gv-gu) <= 15'sd276);
wire occ3 = (gu >= 15'sd246) && (gu <= 15'sd400) &&
 (gv >= 15'sd246) && (gv <= 15'sd388) &&
 ((gu-gv) <= 15'sd96) && ((gv-gu) <= 15'sd84);
wire occ4 = (gu >= 15'sd272) && (gu <= 15'sd398) &&
 (gv >= -15'sd10) && (gv <= 15'sd54) &&
 ((gu-gv) <= 15'sd378) && ((gv-gu) <= -15'sd248);
wire occ5 = (gu >= -15'sd18) && (gu <= 15'sd54) &&
 (gv >= 15'sd264) && (gv <= 15'sd386) &&
 ((gu-gv) <= -15'sd248) && ((gv-gu) <= 15'sd366);
wire occ6 = (gu >= 15'sd424) && (gu <= 15'sd492) &&
 (gv >= 15'sd270) && (gv <= 15'sd388) &&
 ((gu-gv) <= 15'sd188) && ((gv-gu) <= -15'sd70);
wire occluded = occ0 || occ1 || occ2 || occ3 || occ4 || occ5 || occ6;
