/*
 * File: _coder_ekf_soc_step_cg_mex.h
 *
 * MATLAB Coder version            : 25.1
 * C/C++ source code generated on  : 2026-06-05 15:20:07
 */

#ifndef _CODER_EKF_SOC_STEP_CG_MEX_H
#define _CODER_EKF_SOC_STEP_CG_MEX_H

/* Include Files */
#include "emlrt.h"
#include "mex.h"
#include "tmwtypes.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Function Declarations */
MEXFUNCTION_LINKAGE void mexFunction(int32_T nlhs, mxArray *plhs[],
                                     int32_T nrhs, const mxArray *prhs[]);

emlrtCTX mexFunctionCreateRootTLS(void);

void unsafe_ekf_soc_step_cg_mexFunction(int32_T nlhs, mxArray *plhs[3],
                                        int32_T nrhs, const mxArray *prhs[5]);

#ifdef __cplusplus
}
#endif

#endif
/*
 * File trailer for _coder_ekf_soc_step_cg_mex.h
 *
 * [EOF]
 */
