/* SPDX-License-Identifier: GPL-2.0 */
#ifndef PICTERS_MCA_VENDOR_ABI_H
#define PICTERS_MCA_VENDOR_ABI_H

/* Opaque direct imports; vendor.symvers pins the captured export CRCs. */
struct mca_votable;
extern struct mca_votable *mca_find_votable(const char *name);
extern int mca_vote(struct mca_votable *votable, const char *client,
		    bool enabled, int value);

extern int mca_get_effective_result(struct mca_votable *votable);
extern const char *mca_get_effective_client(struct mca_votable *votable);

#endif
